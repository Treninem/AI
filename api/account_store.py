from __future__ import annotations

import hashlib
import hmac
import json
import secrets
import sqlite3
import time
from pathlib import Path
from typing import Any

from api.database import AuroraDatabase


USER_SCOPES = [
    "chat",
    "conversations.read",
    "files",
    "models.read",
    "sync",
    "tools.read",
]


class AccountError(RuntimeError):
    pass


class AuthenticationError(AccountError):
    pass


class RefreshReplayError(AuthenticationError):
    pass


class ConflictError(AccountError):
    pass


class AccountStore:
    """Transactional account/guest/device/session identity store.

    API integration keys remain a separate trust surface. Personal Windows and
    Android sessions use opaque access/refresh tokens whose hashes are stored in
    SQLite. Refresh tokens rotate on every use; replay revokes the whole token
    family. Guest identities are independent principals and can later be moved
    transactionally into an account by SyncStore without exposing client-supplied
    user IDs as authorization authority.
    """

    PASSWORD_PARAMS = {"name": "scrypt", "n": 16384, "r": 8, "p": 1, "dklen": 32}

    def __init__(
        self,
        root: Path,
        *,
        access_ttl: int = 15 * 60,
        refresh_ttl: int = 30 * 24 * 60 * 60,
        verification_ttl: int = 24 * 60 * 60,
        reset_ttl: int = 60 * 60,
    ):
        self.root = root.resolve()
        self.root.mkdir(parents=True, exist_ok=True)
        self.database = AuroraDatabase(self.root / "aurorafox.sqlite3")
        self.access_ttl = max(60, int(access_ttl))
        self.refresh_ttl = max(self.access_ttl, int(refresh_ttl))
        self.verification_ttl = max(300, int(verification_ttl))
        self.reset_ttl = max(300, int(reset_ttl))

    @staticmethod
    def _now() -> int:
        return int(time.time())

    @staticmethod
    def _token(prefix: str) -> str:
        return f"{prefix}_{secrets.token_urlsafe(32)}"

    @staticmethod
    def _hash_token(token: str) -> str:
        return hashlib.sha256(token.encode("utf-8")).hexdigest()

    @staticmethod
    def _normalize_email(email: str) -> str:
        normalized = str(email).strip().casefold()
        if len(normalized) > 320 or normalized.count("@") != 1:
            raise AccountError("Invalid email address")
        local, domain = normalized.split("@", 1)
        if not local or not domain or "." not in domain:
            raise AccountError("Invalid email address")
        return normalized

    @classmethod
    def _password_digest(cls, password: str, salt: bytes, params: dict[str, Any] | None = None) -> str:
        if len(password) < 10 or len(password) > 1024:
            raise AccountError("Password must contain between 10 and 1024 characters")
        selected = dict(cls.PASSWORD_PARAMS)
        if isinstance(params, dict):
            for key in ("n", "r", "p", "dklen"):
                if key in params:
                    selected[key] = int(params[key])
        digest = hashlib.scrypt(
            password.encode("utf-8"),
            salt=salt,
            n=int(selected["n"]),
            r=int(selected["r"]),
            p=int(selected["p"]),
            dklen=int(selected["dklen"]),
        )
        return digest.hex()

    @classmethod
    def _new_password(cls, password: str) -> tuple[str, str, str]:
        salt = secrets.token_bytes(16)
        digest = cls._password_digest(password, salt)
        return salt.hex(), digest, json.dumps(cls.PASSWORD_PARAMS, separators=(",", ":"), sort_keys=True)

    @classmethod
    def _password_matches(cls, password: str, salt_hex: str, digest_hex: str, params_json: str) -> bool:
        try:
            params = json.loads(params_json)
            candidate = cls._password_digest(password, bytes.fromhex(salt_hex), params)
        except Exception:
            return False
        return hmac.compare_digest(candidate, digest_hex)

    @staticmethod
    def _account_public(row: Any) -> dict[str, Any]:
        return {
            "id": str(row["id"]),
            "email": str(row["email_norm"]),
            "display_name": str(row["display_name"]),
            "created_at": int(row["created_at"]),
            "updated_at": int(row["updated_at"]),
            "email_verified": row["email_verified_at"] is not None,
            "disabled": row["disabled_at"] is not None,
        }

    @staticmethod
    def _device_public(row: Any) -> dict[str, Any]:
        return {
            "id": str(row["id"]),
            "name": str(row["name"]),
            "platform": str(row["platform"]),
            "created_at": int(row["created_at"]),
            "last_seen_at": int(row["last_seen_at"]),
            "revoked": row["revoked_at"] is not None,
        }

    def _issue_account_token(self, connection: sqlite3.Connection, account_id: str, purpose: str, ttl: int) -> str:
        now = self._now()
        token = self._token("af_verify" if purpose == "verify_email" else "af_reset")
        connection.execute(
            "UPDATE account_tokens SET revoked_at=? WHERE account_id=? AND purpose=? "
            "AND used_at IS NULL AND revoked_at IS NULL",
            (now, account_id, purpose),
        )
        connection.execute(
            "INSERT INTO account_tokens(id, account_id, purpose, token_hash, created_at, expires_at) "
            "VALUES(?, ?, ?, ?, ?, ?)",
            (
                secrets.token_hex(16),
                account_id,
                purpose,
                self._hash_token(token),
                now,
                now + ttl,
            ),
        )
        return token

    def register(self, email: str, password: str, display_name: str = "") -> dict[str, Any]:
        email_norm = self._normalize_email(email)
        name = str(display_name).strip()[:128] or email_norm.split("@", 1)[0]
        salt, digest, params = self._new_password(password)
        now = self._now()
        account_id = secrets.token_hex(16)
        try:
            with self.database.connection(write=True) as connection:
                connection.execute(
                    "INSERT INTO accounts(id, email_norm, display_name, password_salt, password_hash, "
                    "password_params_json, created_at, updated_at) VALUES(?, ?, ?, ?, ?, ?, ?, ?)",
                    (account_id, email_norm, name, salt, digest, params, now, now),
                )
                verification_token = self._issue_account_token(
                    connection, account_id, "verify_email", self.verification_ttl
                )
        except sqlite3.IntegrityError as exc:
            raise ConflictError("An account with this email already exists") from exc
        return {
            "account": {
                "id": account_id,
                "email": email_norm,
                "display_name": name,
                "created_at": now,
                "updated_at": now,
                "email_verified": False,
                "disabled": False,
            },
            "verification_token": verification_token,
        }

    def verify_email(self, token: str) -> dict[str, Any]:
        digest = self._hash_token(token)
        now = self._now()
        with self.database.connection(write=True) as connection:
            row = connection.execute(
                "SELECT t.id, t.account_id, t.expires_at, t.used_at, t.revoked_at "
                "FROM account_tokens t WHERE t.token_hash=? AND t.purpose='verify_email' LIMIT 1",
                (digest,),
            ).fetchone()
            if row is None or row["used_at"] is not None or row["revoked_at"] is not None:
                raise AuthenticationError("Invalid or already used verification token")
            if int(row["expires_at"]) < now:
                raise AuthenticationError("Verification token expired")
            connection.execute("UPDATE account_tokens SET used_at=? WHERE id=?", (now, str(row["id"])))
            connection.execute(
                "UPDATE accounts SET email_verified_at=COALESCE(email_verified_at, ?), updated_at=? WHERE id=?",
                (now, now, str(row["account_id"])),
            )
            account = connection.execute("SELECT * FROM accounts WHERE id=?", (str(row["account_id"]),)).fetchone()
        return self._account_public(account)

    def resend_verification(self, email: str) -> str | None:
        email_norm = self._normalize_email(email)
        with self.database.connection(write=True) as connection:
            row = connection.execute(
                "SELECT id, email_verified_at, disabled_at FROM accounts WHERE email_norm=?",
                (email_norm,),
            ).fetchone()
            if row is None or row["disabled_at"] is not None or row["email_verified_at"] is not None:
                return None
            return self._issue_account_token(
                connection, str(row["id"]), "verify_email", self.verification_ttl
            )

    def request_password_reset(self, email: str) -> str | None:
        email_norm = self._normalize_email(email)
        with self.database.connection(write=True) as connection:
            row = connection.execute(
                "SELECT id, disabled_at FROM accounts WHERE email_norm=?",
                (email_norm,),
            ).fetchone()
            if row is None or row["disabled_at"] is not None:
                return None
            return self._issue_account_token(connection, str(row["id"]), "reset_password", self.reset_ttl)

    def reset_password(self, token: str, new_password: str) -> None:
        salt, digest, params = self._new_password(new_password)
        token_hash = self._hash_token(token)
        now = self._now()
        with self.database.connection(write=True) as connection:
            row = connection.execute(
                "SELECT id, account_id, expires_at, used_at, revoked_at FROM account_tokens "
                "WHERE token_hash=? AND purpose='reset_password' LIMIT 1",
                (token_hash,),
            ).fetchone()
            if row is None or row["used_at"] is not None or row["revoked_at"] is not None:
                raise AuthenticationError("Invalid or already used password reset token")
            if int(row["expires_at"]) < now:
                raise AuthenticationError("Password reset token expired")
            account_id = str(row["account_id"])
            connection.execute("UPDATE account_tokens SET used_at=? WHERE id=?", (now, str(row["id"])))
            connection.execute(
                "UPDATE account_tokens SET revoked_at=? WHERE account_id=? AND purpose='reset_password' "
                "AND used_at IS NULL AND revoked_at IS NULL",
                (now, account_id),
            )
            connection.execute(
                "UPDATE accounts SET password_salt=?, password_hash=?, password_params_json=?, updated_at=? WHERE id=?",
                (salt, digest, params, now, account_id),
            )
            self._revoke_account_sessions(connection, account_id, now)

    def create_guest(self, device_name: str, platform: str) -> dict[str, Any]:
        now = self._now()
        guest_id = secrets.token_hex(16)
        device_id = secrets.token_hex(16)
        token = self._token("af_guest")
        with self.database.connection(write=True) as connection:
            connection.execute(
                "INSERT INTO guests(id, token_hash, created_at, updated_at) VALUES(?, ?, ?, ?)",
                (guest_id, self._hash_token(token), now, now),
            )
            connection.execute(
                "INSERT INTO devices(id, guest_id, name, platform, created_at, last_seen_at) "
                "VALUES(?, ?, ?, ?, ?, ?)",
                (device_id, guest_id, str(device_name).strip()[:128] or "Guest device", str(platform).strip()[:64], now, now),
            )
        return {
            "guest_token": token,
            "guest_id": guest_id,
            "device_id": device_id,
            "created_at": now,
        }

    def _create_or_reuse_device(
        self,
        connection: sqlite3.Connection,
        account_id: str,
        device_name: str,
        platform: str,
        device_id: str | None,
        now: int,
    ) -> str:
        if device_id:
            row = connection.execute(
                "SELECT id, account_id, revoked_at FROM devices WHERE id=?",
                (device_id,),
            ).fetchone()
            if row is None or str(row["account_id"] or "") != account_id or row["revoked_at"] is not None:
                raise AuthenticationError("Unknown or revoked device")
            connection.execute(
                "UPDATE devices SET name=?, platform=?, last_seen_at=? WHERE id=?",
                (str(device_name).strip()[:128] or "AuroraFox device", str(platform).strip()[:64], now, device_id),
            )
            return device_id
        new_id = secrets.token_hex(16)
        connection.execute(
            "INSERT INTO devices(id, account_id, name, platform, created_at, last_seen_at) VALUES(?, ?, ?, ?, ?, ?)",
            (
                new_id,
                account_id,
                str(device_name).strip()[:128] or "AuroraFox device",
                str(platform).strip()[:64],
                now,
                now,
            ),
        )
        return new_id

    def _issue_session(
        self,
        connection: sqlite3.Connection,
        account_id: str,
        device_id: str,
        now: int,
    ) -> dict[str, Any]:
        session_id = secrets.token_hex(16)
        family_id = secrets.token_hex(16)
        access = self._token("af_access")
        refresh = self._token("af_refresh")
        connection.execute(
            "INSERT INTO auth_sessions(id, account_id, device_id, family_id, access_hash, access_expires_at, "
            "created_at, last_seen_at) VALUES(?, ?, ?, ?, ?, ?, ?, ?)",
            (
                session_id,
                account_id,
                device_id,
                family_id,
                self._hash_token(access),
                now + self.access_ttl,
                now,
                now,
            ),
        )
        connection.execute(
            "INSERT INTO refresh_tokens(id, session_id, family_id, token_hash, generation, created_at, expires_at) "
            "VALUES(?, ?, ?, ?, 0, ?, ?)",
            (
                secrets.token_hex(16),
                session_id,
                family_id,
                self._hash_token(refresh),
                now,
                now + self.refresh_ttl,
            ),
        )
        return {
            "access_token": access,
            "access_expires_at": now + self.access_ttl,
            "refresh_token": refresh,
            "refresh_expires_at": now + self.refresh_ttl,
            "session_id": session_id,
            "device_id": device_id,
        }

    def login(
        self,
        email: str,
        password: str,
        device_name: str,
        platform: str,
        device_id: str | None = None,
    ) -> dict[str, Any]:
        email_norm = self._normalize_email(email)
        now = self._now()
        with self.database.connection(write=True) as connection:
            row = connection.execute("SELECT * FROM accounts WHERE email_norm=?", (email_norm,)).fetchone()
            if row is None or row["disabled_at"] is not None:
                raise AuthenticationError("Invalid email or password")
            if not self._password_matches(
                password,
                str(row["password_salt"]),
                str(row["password_hash"]),
                str(row["password_params_json"]),
            ):
                raise AuthenticationError("Invalid email or password")
            resolved_device = self._create_or_reuse_device(
                connection, str(row["id"]), device_name, platform, device_id, now
            )
            session = self._issue_session(connection, str(row["id"]), resolved_device, now)
            account = self._account_public(row)
        return {"account": account, **session}

    def _revoke_family(self, connection: sqlite3.Connection, family_id: str, now: int) -> None:
        connection.execute(
            "UPDATE auth_sessions SET revoked_at=COALESCE(revoked_at, ?) WHERE family_id=?",
            (now, family_id),
        )
        connection.execute(
            "UPDATE refresh_tokens SET revoked_at=COALESCE(revoked_at, ?) WHERE family_id=?",
            (now, family_id),
        )

    def _revoke_account_sessions(self, connection: sqlite3.Connection, account_id: str, now: int) -> None:
        families = [
            str(row["family_id"])
            for row in connection.execute(
                "SELECT DISTINCT family_id FROM auth_sessions WHERE account_id=? AND revoked_at IS NULL",
                (account_id,),
            ).fetchall()
        ]
        for family_id in families:
            self._revoke_family(connection, family_id, now)

    def refresh(self, refresh_token: str) -> dict[str, Any]:
        digest = self._hash_token(refresh_token)
        now = self._now()
        failure: AuthenticationError | None = None
        access = ""
        refresh = ""
        with self.database.connection(write=True) as connection:
            row = connection.execute(
                "SELECT r.id AS refresh_id, r.session_id, r.family_id, r.generation, r.expires_at, "
                "r.consumed_at, r.revoked_at AS refresh_revoked, s.account_id, s.device_id, "
                "s.revoked_at AS session_revoked, d.revoked_at AS device_revoked, a.disabled_at "
                "FROM refresh_tokens r JOIN auth_sessions s ON s.id=r.session_id "
                "JOIN devices d ON d.id=s.device_id JOIN accounts a ON a.id=s.account_id "
                "WHERE r.token_hash=? LIMIT 1",
                (digest,),
            ).fetchone()
            if row is None:
                raise AuthenticationError("Invalid refresh token")
            family_id = str(row["family_id"])
            if row["consumed_at"] is not None or row["refresh_revoked"] is not None:
                self._revoke_family(connection, family_id, now)
                failure = RefreshReplayError("Refresh token replay detected; session family revoked")
            elif (
                int(row["expires_at"]) < now
                or row["session_revoked"] is not None
                or row["device_revoked"] is not None
                or row["disabled_at"] is not None
            ):
                self._revoke_family(connection, family_id, now)
                failure = AuthenticationError("Refresh token expired or revoked")
            else:
                access = self._token("af_access")
                refresh = self._token("af_refresh")
                generation = int(row["generation"]) + 1
                connection.execute(
                    "UPDATE refresh_tokens SET consumed_at=? WHERE id=?",
                    (now, str(row["refresh_id"])),
                )
                connection.execute(
                    "UPDATE auth_sessions SET access_hash=?, access_expires_at=?, last_seen_at=? WHERE id=?",
                    (self._hash_token(access), now + self.access_ttl, now, str(row["session_id"])),
                )
                connection.execute(
                    "UPDATE devices SET last_seen_at=? WHERE id=?",
                    (now, str(row["device_id"])),
                )
                connection.execute(
                    "INSERT INTO refresh_tokens(id, session_id, family_id, token_hash, generation, created_at, expires_at) "
                    "VALUES(?, ?, ?, ?, ?, ?, ?)",
                    (
                        secrets.token_hex(16),
                        str(row["session_id"]),
                        family_id,
                        self._hash_token(refresh),
                        generation,
                        now,
                        now + self.refresh_ttl,
                    ),
                )
        if failure is not None:
            raise failure
        return {
            "access_token": access,
            "access_expires_at": now + self.access_ttl,
            "refresh_token": refresh,
            "refresh_expires_at": now + self.refresh_ttl,
            "session_id": str(row["session_id"]),
            "device_id": str(row["device_id"]),
        }

    def verify_access(self, token: str) -> dict[str, Any] | None:
        if not token.startswith("af_access_"):
            return None
        now = self._now()
        digest = self._hash_token(token)
        with self.database.connection() as connection:
            row = connection.execute(
                "SELECT s.id AS session_id, s.account_id, s.device_id, s.access_hash, s.access_expires_at, "
                "s.revoked_at AS session_revoked, a.email_norm, a.display_name, a.disabled_at, "
                "d.revoked_at AS device_revoked FROM auth_sessions s "
                "JOIN accounts a ON a.id=s.account_id JOIN devices d ON d.id=s.device_id "
                "WHERE s.access_hash=? LIMIT 1",
                (digest,),
            ).fetchone()
        if row is None:
            return None
        if (
            row["session_revoked"] is not None
            or row["device_revoked"] is not None
            or row["disabled_at"] is not None
            or int(row["access_expires_at"]) < now
            or not hmac.compare_digest(digest, str(row["access_hash"]))
        ):
            return None
        account_id = str(row["account_id"])
        return {
            "id": f"account:{account_id}",
            "principal_kind": "account",
            "principal_id": account_id,
            "session_id": str(row["session_id"]),
            "device_id": str(row["device_id"]),
            "email": str(row["email_norm"]),
            "display_name": str(row["display_name"]),
            "scopes": list(USER_SCOPES),
            "auth_kind": "account_session",
        }

    def verify_guest(self, token: str) -> dict[str, Any] | None:
        if not token.startswith("af_guest_"):
            return None
        digest = self._hash_token(token)
        with self.database.connection() as connection:
            row = connection.execute(
                "SELECT g.id AS guest_id, g.token_hash, g.revoked_at AS guest_revoked, g.migrated_to_account, "
                "d.id AS device_id, d.revoked_at AS device_revoked FROM guests g "
                "JOIN devices d ON d.guest_id=g.id WHERE g.token_hash=? LIMIT 1",
                (digest,),
            ).fetchone()
        if row is None:
            return None
        if (
            row["guest_revoked"] is not None
            or row["device_revoked"] is not None
            or row["migrated_to_account"] is not None
            or not hmac.compare_digest(digest, str(row["token_hash"]))
        ):
            return None
        guest_id = str(row["guest_id"])
        return {
            "id": f"guest:{guest_id}",
            "principal_kind": "guest",
            "principal_id": guest_id,
            "device_id": str(row["device_id"]),
            "scopes": list(USER_SCOPES),
            "auth_kind": "guest_session",
        }

    def verify_personal_token(self, token: str) -> dict[str, Any] | None:
        return self.verify_access(token) or self.verify_guest(token)

    def revoke_access(self, token: str) -> bool:
        record = self.verify_access(token)
        if record is None:
            return False
        now = self._now()
        with self.database.connection(write=True) as connection:
            row = connection.execute(
                "SELECT family_id FROM auth_sessions WHERE id=? AND revoked_at IS NULL",
                (str(record["session_id"]),),
            ).fetchone()
            if row is None:
                return False
            self._revoke_family(connection, str(row["family_id"]), now)
        return True

    def list_devices(self, account_id: str) -> list[dict[str, Any]]:
        with self.database.connection() as connection:
            rows = connection.execute(
                "SELECT id, name, platform, created_at, last_seen_at, revoked_at FROM devices "
                "WHERE account_id=? ORDER BY last_seen_at DESC, id",
                (account_id,),
            ).fetchall()
        return [self._device_public(row) for row in rows]

    def revoke_device(self, account_id: str, device_id: str, *, except_session_id: str = "") -> bool:
        now = self._now()
        with self.database.connection(write=True) as connection:
            row = connection.execute(
                "SELECT id, revoked_at FROM devices WHERE id=? AND account_id=?",
                (device_id, account_id),
            ).fetchone()
            if row is None or row["revoked_at"] is not None:
                return False
            connection.execute("UPDATE devices SET revoked_at=? WHERE id=?", (now, device_id))
            sessions = connection.execute(
                "SELECT id, family_id FROM auth_sessions WHERE device_id=? AND revoked_at IS NULL",
                (device_id,),
            ).fetchall()
            for session in sessions:
                if except_session_id and str(session["id"]) == except_session_id:
                    continue
                self._revoke_family(connection, str(session["family_id"]), now)
        return True
