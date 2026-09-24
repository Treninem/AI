# AuroraFox — инженерная память ошибок и обходов

> Постоянный технический справочник для ChatGPT Chat, Work, Codex, локальных/серверных агентов и автоматизаций, работающих с `Treninem/AI`.
>
> Это **не второй журнал проекта**. CLAIM, текущий статус, commits, CI evidence и NEXT ведутся только в `docs/PROJECT_MASTER_LOG.md`. Здесь хранятся повторно применимые причины сбоев, проверенные исправления и профилактика.

## Обязательный порядок использования

Перед планированием или изменением AuroraFox исполнитель обязан:

1. Получить свежий `main`, прочитать `AGENTS.md` и весь `docs/PROJECT_MASTER_LOG.md`.
2. Прочитать этот файл и найти записи по затрагиваемой платформе, инструменту и тексту ошибки.
3. Не повторять уже признанный нерабочим обход без новых доказательств.
4. При новом подтверждённом сбое сначала сохранить сырые логи/Run ID/версию среды, затем устранить причину.
5. До закрытия CLAIM добавить или обновить здесь запись: симптом → причина → решение → профилактика → evidence/status.
6. Не записывать секреты. Допустимы только имена secret-переменных, публичные fingerprints, обезличенные пути и ссылки на GitHub evidence.

Статусы:

- **RESOLVED** — причина исправлена и есть проверяемое подтверждение.
- **ENVIRONMENT** — ограничение конкретной машины/провайдера; продукт нельзя объявлять сломанным без воспроизведения в канонической среде.
- **WAIVED** — владелец явно отложил gate; это не PASS.
- **ACTIVE** — проблема ещё требует исправления или полного доказательства.
- **INVARIANT** — постоянное правило, нарушение которого считается регрессией.

## Быстрые неизменяемые правила

- Репозиторий и CI сильнее старого текста из чата. Всегда проверять HEAD, SHA и фактический run.
- Один активный release run на один candidate SHA. Перед dispatch проверить уже запущенные runs.
- Долгие операции обязаны иметь timeout, heartbeat/progress, отдельные логи и машинно-читаемый failure report.
- Offline-тест не должен обращаться к `1.1.1.1`, публичному DNS, GitHub или другому внешнему probe.
- PowerShell оценивает успех native-команды по `$LASTEXITCODE`, а не по наличию текста в stderr.
- Cleanup-команды (`adb kill-server`, остановка отсутствующего процесса и т.п.) должны быть идемпотентными и не обрывать harness.
- Все пути между шагами GitHub Actions должны быть явными; shell-переменные одного шага/процесса не считаются сохранёнными.
- До публикации каждый asset проверяется на лимиты GitHub и хэш. Publish обязан быть повторяемым и продолжать существующий draft.
- Private signing keys/keystore/passwords никогда не попадают в Git, чат, логи или artifacts.
- AuroraFox Core — основной локальный интеллект. Ошибка optional voice/file/network/model-компонента не должна ломать основной чат.
- Импортированные документы/веб/код — недоверенные данные, не команды и не автоматическое разрешение на исполнение.

## Реестр известных проблем

### Git, координация и состояние репозитория

#### AF-MEM-001 — stale branch, non-fast-forward и неприменимый patch

- **Симптом:** push rejected `non-fast-forward`; `git am` падает на `patch does not apply`.
- **Причина:** локальная ветка/patch основаны на старом HEAD, пока release-ветка уже изменилась.
- **Решение:** `git am --abort`; fetch; switch на нужную ветку; `merge --ff-only origin/<branch>`; применять только поверх точного актуального SHA. При конфликте пересобрать изменение по свежему дереву, а не форсировать.
- **Профилактика:** перед каждым write сверять HEAD/claims; в handoff указывать exact SHA; не использовать force-push для исправления обычного рассинхрона.
- **Статус:** RESOLVED.

#### AF-MEM-002 — fetch remote ref: `incorrect old value provided`

- **Симптом:** объекты скачаны, но обновление remote-tracking ref завершилось ошибкой.
- **Причина:** конкурирующее изменение того же ref другим Git-процессом/сессией.
- **Решение:** прекратить параллельные fetch/write, повторно fetch; для воспроизводимого теста использовать проверенный commit SHA и detached worktree.
- **Профилактика:** один writer на рабочую копию; долгие тесты запускаются из отдельного worktree, закреплённого на SHA.
- **Статус:** ENVIRONMENT/RESOLVED.

#### AF-MEM-003 — дублирующиеся release dispatch

- **Симптом:** одновременно запущены два полных Release workflow, один пришлось отменять.
- **Причина:** повторный dispatch без проверки существующего run.
- **Решение:** оставить один run для exact SHA, отменить дубликат.
- **Профилактика:** перед dispatch запросить последние runs по workflow/branch/SHA; сохранить один Run ID в master log.
- **Статус:** RESOLVED.

#### AF-MEM-004 — неверная передача PowerShell member expression в `gh`

- **Симптом:** `gh run view $run.databaseId ...` отвечает `accepts at most 1 arg(s), received 3`.
- **Причина:** неоднозначное разворачивание member expression/массива в native command.
- **Решение:** сначала `$runId = [string]$run.databaseId`, затем `gh run view $runId ...`.
- **Профилактика:** scalar-cast всех IDs и путей перед native CLI.
- **Статус:** RESOLVED.

#### AF-MEM-005 — большой master log был обрезан при API-редактировании

- **Симптом:** после записи через API канонический журнал неожиданно стал короче и потерял исторические разделы; позднее пришлось восстанавливать полное 3047-строчное дерево.
- **Причина:** в update был передан только отображённый/line-limited/truncated фрагмент вместо полного исходного содержимого.
- **Решение:** восстановить файл из последнего полного tree/commit; для append/update всегда получать полный blob и текущий blob SHA.
- **Профилактика:** никогда не заменять `PROJECT_MASTER_LOG.md` содержимым preview, excerpt или вывода с пометкой `truncated`; до commit проверять, что прежний byte/line count не уменьшился без явной задачи на сокращение.
- **Статус:** RESOLVED/INVARIANT.

#### AF-MEM-006 — `main` отставал от release branch

- **Симптом:** release evidence/guards видят разные истории; `main` был на сотни commits позади финализационной ветки.
- **Причина:** длительная работа велась в release branch без своевременной интеграции.
- **Решение:** доказать ancestry и выполнить только fast-forward `main` к проверенному candidate, без merge rewrite.
- **Профилактика:** перед RC фиксировать единственный exact SHA, ancestry `main`↔release и ветку, из которой создаётся tag.
- **Статус:** RESOLVED.

### Windows PowerShell и инструменты

#### AF-MEM-010 — native stderr превращается в terminating error

- **Симптом:** успешная/продолжаемая команда (`sdkmanager`, `adb`, OpenSSL) обрывает скрипт с `NativeCommandError` при `$ErrorActionPreference='Stop'`.
- **Причина:** Windows PowerShell 5.1 оборачивает stderr native-процесса как error record; warning ошибочно считается отказом.
- **Решение:** запускать чувствительные native tools через `ProcessStartInfo` с раздельным stdout/stderr и проверять exit code; либо локально ослаблять preference только вокруг ожидаемой команды и немедленно проверять `$LASTEXITCODE`.
- **Профилактика:** helper для native execution; tests на warning-to-stderr; stderr сохранять в diagnostics.
- **Evidence:** Android `sdkmanager.bat` deprecation warning; signing fix commit `aa440d2`.
- **Статус:** RESOLVED/INVARIANT.

#### AF-MEM-011 — Windows PowerShell 5.1 не поддерживает modern RSA export API

- **Симптом:** `RSACng does not contain a method named ExportPkcs8PrivateKey`.
- **Причина:** скрипт полагался на API новой .NET, отсутствующий в Windows PowerShell 5.1.
- **Решение:** транзакционный генератор через OpenSSL из Git for Windows: temp-dir, validate, atomic install, cleanup при ошибке.
- **Профилактика:** release bootstrap тестировать именно в Windows PowerShell 5.1; не считать PowerShell 7 эквивалентной средой.
- **Evidence:** commit `aa440d2`.
- **Статус:** RESOLVED.

#### AF-MEM-012 — отсутствующие `gh`, `pytest`, `bash` или Python-модули

- **Симптом:** readiness падает на `gh is not recognized`, `No module named pytest`, `bash is not recognized`, `pypdfium2`/Pillow/FastAPI dependencies missing.
- **Причина:** запуск в неинициализированной среде или не тем interpreter/OS.
- **Решение:** выполнять preflight инструментов до тяжёлых тестов; фиксировать exact Python; ставить зависимости в изолированную venv; Linux deploy scripts запускать на сервере через SSH, не в Windows PowerShell.
- **Профилактика:** единый bootstrap/preflight с версиями и actionable diagnostics; GitHub Actions — каноническая чистая среда.
- **Статус:** RESOLVED/INVARIANT.

#### AF-MEM-013 — PowerShell ExecutionPolicy блокирует `npm.ps1`

- **Симптом:** `PSSecurityException` для `npm -v`/установки CLI.
- **Причина:** PowerShell выбирает заблокированный shim `npm.ps1`.
- **Решение:** использовать `npm.cmd` либо согласованно менять policy только в допустимом scope.
- **Профилактика:** Windows-инструкции должны явно различать `.ps1` и `.cmd`.
- **Статус:** ENVIRONMENT.

#### AF-MEM-014 — warning принимается за root cause

- **Симптом:** диагностика останавливается на PyInstaller `Hidden import not found`/deprecation warnings, хотя package и installer продолжают успешно собираться.
- **Причина:** выбран самый заметный stderr, а не первый terminating step/exit code.
- **Решение:** читать job до первого реально failed step и его конечного exception; warnings классифицировать отдельно.
- **Профилактика:** в отчёте всегда указывать `failing job → failing step → final error → preceding successful gates`.
- **Статус:** INVARIANT.

### Android SDK, emulator и release APK

#### AF-MEM-020 — SDK / cmdline-tools / system image не установлены

- **Симптом:** SDK not found; `sdkmanager.bat` missing; `package.xml=False` для API 35 image.
- **Причина:** Android Studio установлена, но нужные SDK Tools/Platform-Tools/Emulator/Command-line Tools или image не выбраны.
- **Решение:** использовать `%LOCALAPPDATA%\Android\Sdk`; установить Platform-Tools, Emulator, Command-line Tools (latest), Android 15/API 35 Google APIs x86_64 image; проверять конкретные executable/package.xml.
- **Профилактика:** orchestrator preflight перечисляет отсутствующий компонент и точный путь до начала build.
- **Статус:** RESOLVED.

#### AF-MEM-021 — Android CLI download `connection refused`

- **Симптом:** `Failed to connect to remote repository` / download from `dl.google.com` refused.
- **Причина:** сеть/proxy/firewall блокирует repository download.
- **Решение:** установить компоненты из Android Studio SDK Manager в доступной сети или настроить разрешённый proxy; после наличия компонентов локальный test не требует сети.
- **Профилактика:** отделять download/bootstrap от offline acceptance; кэшировать проверенные SDK components.
- **Статус:** ENVIRONMENT.

#### AF-MEM-022 — hardware acceleration unavailable

- **Симптом:** emulator `accel: 6`; hypervisor driver absent.
- **Причина:** выключена CPU virtualization/WHPX или не установлен Windows Hypervisor Platform.
- **Решение:** включить virtualization и Windows Hypervisor Platform, reboot; подтвердить `emulator -accel-check` → `WHPX ... installed and usable`.
- **Профилактика:** fail-fast preflight до создания/запуска AVD.
- **Статус:** RESOLVED.

#### AF-MEM-023 — `JAVA_HOME` отсутствует

- **Симптом:** AVD не создаётся: `JAVA_HOME is not set and no java command`.
- **Причина:** Android tools не нашли JDK.
- **Решение:** использовать Android Studio JBR, например `%ProgramFiles%\Android\Android Studio\jbr`, добавить `bin` в процессный PATH, проверить `java -version`.
- **Профилактика:** orchestrator сам обнаруживает JBR и печатает выбранную Java.
- **Статус:** RESOLVED.

#### AF-MEM-024 — ADB cleanup обрывает harness

- **Симптом:** `adb kill-server` возвращает connection refused и PowerShell завершает run.
- **Причина:** идемпотентная cleanup-команда ошибочно обрабатывается как обязательная.
- **Решение:** cleanup выполнять best-effort; затем отдельно `adb start-server` и проверять `adb devices`.
- **Профилактика:** cleanup helper принимает `not running/not found` как success, но сохраняет неожиданные ошибки.
- **Статус:** RESOLVED.

#### AF-MEM-025 — emulator постоянно `offline`/QEMU hang на локальном ПК

- **Симптом:** `emulator-5554 offline` часами; reconnect не помогает; crashpad сообщает hanging `QEMU2 CPU` threads; software OpenGL missing, SwiftShader/Vulkan/GLDirectMem hangs.
- **Причина:** несовместимость конкретной Windows/GPU/emulator 37.1.11 среды; смена GPU flags и downgrade 36.6.11 не дали надёжного локального device proof.
- **Решение:** остановить бесконечный локальный retry; собрать подробные logs; классифицировать как environment-specific и выполнить канонический Android 35 emulator gate в GitHub Actions.
- **Профилактика:** boot timeout 10–15 минут, heartbeat, ADB state/logcat/crash logs, не ждать 8 часов; не считать WAIVED тест пройденным.
- **Evidence:** GitHub Release candidate Android emulator gate позднее прошёл; локальный owner-PC gate был отложен.
- **Статус:** ENVIRONMENT; canonical CI resolved.

#### AF-MEM-026 — shell-переменная APK потерялась между workflow commands

- **Симптом:** `adb: filename doesn't end .apk or .apex:` с пустым именем, хотя signed APK собран и проверен.
- **Причина:** `apk=...` и `adb install "$apk"` выполнялись отдельными shells.
- **Решение:** передавать явный путь `dist/AuroraFox-Android.apk` в том же step.
- **Профилактика:** contract-test запрещает локальную переменную в этом блоке; между steps использовать outputs/`GITHUB_ENV`.
- **Статус:** RESOLVED.

### Runtime, UI и offline-поведение

#### AF-MEM-030 — UI показывает «локальные модели временно исключены»

- **Симптом:** основной чат отвечает сообщением об ошибке модели вместо ответа; пользователь опасается требования внешней модели.
- **Причина:** bootstrap/failover path мог переводить local models в quarantine и выводить технический failure как пользовательский ответ.
- **Решение:** bundled AuroraFox Core — normal primary path; external providers только explicit compatibility; bounded retry/fallback внутри local Core; optional subsystem failure не заменяет ответ общим model error.
- **Профилактика:** offline chat smoke без Ollama/API/Internet; UI test запрещает прежний текст ошибки в normal path.
- **Статус:** RESOLVED contractually; проверять в каждом packaged smoke.

#### AF-MEM-031 — неправильная/неполная иконка приложения

- **Симптом:** taskbar/installer показывали стандартную или старую иконку, отличную от owner-provided AuroraFox image.
- **Причина:** branding asset не был синхронизирован во всех export/installer/window surfaces.
- **Решение:** один канонический owner-provided icon asset для project/window/Windows installer/executable/Android launcher.
- **Профилактика:** release branding contract проверяет все ссылки и отсутствие placeholder; visual smoke остаётся обязательным.
- **Статус:** RESOLVED contractually; визуально проверять final artifacts.

#### AF-MEM-032 — CodeSpecialist обращался к Ollama/устаревшему `base_url`

- **Симптом:** Work smoke падает на удалённом `AIClient.base_url`; normal code path сначала обращается к Ollama coder model.
- **Причина:** stale provider-specific integration нарушала self-primary architecture.
- **Решение:** normal CodeSpecialist делегирует `AIClient.chat()`/bundled Core; compatibility-only API изолирован.
- **Профилактика:** offline self-reliance contract и startup smoke.
- **Статус:** RESOLVED/INVARIANT.

#### AF-MEM-033 — offline smoke зависел от публичного network probe

- **Симптом:** Code Specialist smoke даёт false negative при недоступности `1.1.1.1`.
- **Причина:** внешний connectivity probe использован как предпосылка локальной функции.
- **Решение:** убрать probe из offline acceptance; использовать локальные controllable fixtures.
- **Профилактика:** static contract запрещает публичные IP/URLs в offline tests.
- **Статус:** RESOLVED/INVARIANT.

### Knowledge, файлы, OCR и долгие тесты

#### AF-MEM-040 — 1 GiB Knowledge run зависает/таймаутится

- **Симптом:** многочасовой run без движения; timeout; failure report иногда отсутствует.
- **Причина:** повторные full-store scans/searches по гигабайтам, синхронные участки и недостаточная observability.
- **Решение:** streaming/shards, bounded queries, checkpoints/resume, относительные scaling gates; report писать в `finally` и при timeout.
- **Профилактика:** маленький preflight, heartbeat по shard/phase, hard timeout, RSS/wall-time, exact manifest/state hashes.
- **Evidence:** Windows installed production pack прошёл offline: 60 shards, 75,871 records, 1,924,345,221 bytes; restart skipped 60; `passed=true`.
- **Статус:** RESOLVED для Windows production pack; Android physical gate не подменять.

#### AF-MEM-041 — quadratic/superlinear Knowledge operations

- **Симптом:** N→2N время росло около 3.5–4×; import 1 GiB блокировался повторными поисками.
- **Причина:** source filtering/full rewrite и repeated file open/close на каждую запись/чанк.
- **Решение:** batch/session append, registry/transaction separation, не выполнять лишний full-store rewrite для нового source; сравнивать N/2N/4N.
- **Профилактика:** relative performance blocker вместо простого увеличения timeout; correctness/dedupe/rollback gates сохраняются.
- **Статус:** RESOLVED/monitor.

#### AF-MEM-042 — alias removal удалял canonical knowledge

- **Симптом:** удаление alias/copy удаляло canonical registry и searchable records.
- **Причина:** alias и canonical ownership были смешаны.
- **Решение:** alias removal только detach alias; canonical removal — transaction-scoped snapshot/registry/store commit/rollback.
- **Профилактика:** deterministic alias-removal и process-kill recovery probes.
- **Статус:** RESOLVED.

#### AF-MEM-043 — OCR зависимости/данные отсутствуют

- **Симптом:** Python OCR tests падают без `pypdfium2`; Pillow build требует JPEG headers; Android OCR возвращает пусто без rus+eng data.
- **Причина:** неполная test/runtime dependency assembly.
- **Решение:** предпочитать wheels в isolated venv; явно provision `pypdfium2`; Android package включает и проверяет offline rus+eng OCR data.
- **Профилактика:** dependency preflight и offline OCR fixture до больших package tests.
- **Статус:** RESOLVED where packaged; scanned-PDF quality remains ongoing.

#### AF-MEM-044 — WAIVED тест ошибочно называют PASS

- **Симптом:** тяжёлый Android Knowledge/emulator gate не выполнен, но обсуждается как пройденный.
- **Причина:** смешаны owner waiver и техническое доказательство.
- **Решение:** использовать `OWNER_WAIVED_NOT_EXECUTED`; readiness не повышать как за PASS.
- **Профилактика:** machine-readable status enum и явная граница device/CI/desktop.
- **Статус:** INVARIANT.

#### AF-MEM-045 — Android `packageBenchmark` и огромный bundled model

- **Симптом:** Gradle `:app:packageBenchmark` падает при APK с моделью около 1.28 GiB либо создаёт артефакт, близкий к инфраструктурным лимитам.
- **Причина:** очень большой asset усиливает требования к disk/RAM/ZIP/runner/upload; обычный unit build не проверяет полный packaging path.
- **Решение:** отдельный package job с disk preflight, точным model hash/size, достаточным heap/temp space и проверкой финального APK; не дублировать модель в нескольких путях.
- **Профилактика:** size budget и free-space gate до Gradle/Godot export; release upload limit проверять отдельно от build success.
- **Статус:** RESOLVED для V1.4 CI; monitor.

### Windows package, services и voice

#### AF-MEM-050 — Godot импортирует generated Python/PyInstaller directories

- **Симптом:** package/import раздувается или захватывает `.venv`, cache/build artifacts.
- **Причина:** недостаточные import exclusions.
- **Решение:** исключить generated runtime/build/cache directories из Godot import/package path.
- **Evidence:** fix commit `d6504ba`.
- **Статус:** RESOLVED.

#### AF-MEM-051 — firewall offline-test блокирует loopback

- **Симптом:** voice/service smoke получает Windows `WinError 10013`.
- **Причина:** outbound firewall rule блокировал не только интернет, но и локальный `127.0.0.1` IPC.
- **Решение:** блокировать только external address ranges, явно разрешить loopback.
- **Профилактика:** offline означает «без внешней сети», а не «без локальных sidecars».
- **Статус:** RESOLVED.

#### AF-MEM-052 — backend health timeout из-за working directory

- **Симптом:** упакованный backend стартует, но health не поднимается.
- **Причина:** `Start-Process` запускал exe не из каталога его ресурсов.
- **Решение:** задавать `-WorkingDirectory` каталогу executable.
- **Профилактика:** packaged smoke запускается из произвольного cwd.
- **Статус:** RESOLVED.

#### AF-MEM-053 — Windows smoke ждёт дочерний voice backend бесконечно

- **Симптом:** `Start-Process -Wait` не возвращается после завершения основного приложения.
- **Причина:** дерево процессов содержит долгоживущий `AuroraVoiceBackend`.
- **Решение:** bounded process helper с timeout, PID/tree cleanup и сохранением логов.
- **Evidence:** verified candidate commit `c3693426e34d8c94b23b622a7050f7d78831beb7`.
- **Статус:** RESOLVED.

#### AF-MEM-054 — Inno Setup ссылается на отсутствующий файл

- **Симптом:** installer compile красный при зелёной app export.
- **Причина:** `.iss` содержит stale/missing source path.
- **Решение:** validate every installer source before compile; синхронизировать packaging manifest.
- **Профилактика:** installer file-existence contract и clean-room build.
- **Статус:** RESOLVED.

#### AF-MEM-055 — local service TXT assertion не учитывал newline/kind

- **Симптом:** health endpoint зелёный, но installed local-services smoke падает на сравнении TXT content.
- **Причина:** test сравнивал представление текста без нормализации newline/record kind.
- **Решение:** проверять семантическое значение после нормализации допустимых line endings и точный expected record kind.
- **Профилактика:** fixtures включают CRLF/LF и не смешивают transport formatting с payload correctness.
- **Статус:** RESOLVED.

### Server, SMTP и deployment

#### AF-MEM-060 — REG.RU verify: отсутствует `/etc/aurorafox/account-mail.env`

- **Симптом:** `AURORAFOX_VERIFY_FAIL missing_file=/etc/aurorafox/account-mail.env`.
- **Причина:** production SMTP configuration не создана.
- **Решение:** получить SMTP host/login/sender у реального почтового провайдера; использовать отдельный app password/SMTP password; создать root-readable env на сервере, не в Git.
- **Профилактика:** deploy preflight перечисляет required secret names; credentials никогда не придумывать и не отправлять в чат.
- **Статус:** owner/provider boundary; не является Core dependency.

#### AF-MEM-061 — server verification запущен в Windows

- **Симптом:** PowerShell не знает `bash /opt/aurorafox/.../verify.sh`.
- **Причина:** Linux server path выполнен на owner PC.
- **Решение:** `ssh root@<server>`, затем запускать script на Ubuntu.
- **Профилактика:** команды маркировать `OWNER-PC PowerShell` / `SERVER shell`.
- **Статус:** RESOLVED.

#### AF-MEM-062 — обязательная production network boundary

- **Правило:** SSH только по ключам; password login off; AgentCore/FastMCP не открывать наружу; service слушает loopback; наружу только Nginx/SSL `api.aurorafox.ru`; firewall only required ports; systemd restart/timer/watchdog; logrotate.
- **Причина:** уменьшение attack surface и предсказуемое восстановление.
- **Статус:** INVARIANT.

### Signing, updater и публикация

#### AF-MEM-070 — исторические V1.2/V1.3 не имеют полной trust chain

- **Симптом:** `releases/latest/download/update.json` отсутствовал/404; V1.2/V1.3 не содержали pinned `release_public.pub`; Android CI мог использовать временный keystore.
- **Причина:** permanent signing identity не была закреплена до старых binaries.
- **Решение:** one-time Windows Repair/Bridge до signed floor V1.4; permanent updater/Android identity; дальнейшие updates только с теми же ключами.
- **Профилактика:** не ротировать identity; private material backup вне repo; release contracts проверяют pins/signatures/lineage.
- **Статус:** RESOLVED architecture; historical clients require bridge.

#### AF-MEM-071 — identity reset прервался после удаления public pins

- **Симптом:** bootstrap архивировал/удалил пять tracked public identity files и упал до генерации нового ключа.
- **Причина:** destructive steps выполнялись до проверки совместимости генератора.
- **Решение:** confirmation-guard, preflight tools/auth, private-key absence guard, archive, temp generation/validation, atomic public install, cleanup/restore on failure.
- **Профилактика:** identity changes transactional; normal release never regenerates keys.
- **Статус:** RESOLVED/INVARIANT.

#### AF-MEM-072 — secrets readiness без раскрытия значений

- **Симптом:** release blocked отсутствующими четырьмя secret names.
- **Решение:** guarded `secrets_only=true` job проверяет presence и cryptographic match, не печатает values и пропускает heavy/publish jobs.
- **Обязательные names:** `AURORA_UPDATE_SIGNING_PRIVATE_KEY_BASE64`, `AURORA_ANDROID_KEYSTORE_BASE64`, `AURORA_ANDROID_KEYSTORE_USER`, `AURORA_ANDROID_KEYSTORE_PASSWORD`.
- **Evidence:** run `35922892799` SUCCESS.
- **Статус:** RESOLVED/INVARIANT.

#### AF-MEM-073 — cross-run artifact оказался в `dist/dist`

- **Симптом:** publish не находит ожидаемый Windows artifact после download.
- **Причина:** multi-path artifact сохраняет внутреннюю `dist/` структуру, а download target тоже назван `dist`.
- **Решение:** скачивать во staging и нормализовать найденные exact filenames в один release directory.
- **Профилактика:** layout step печатает inventory, требует ровно один match и сверяет hash.
- **Статус:** RESOLVED.

#### AF-MEM-074 — GitHub Release asset превышает 2 GiB

- **Симптом:** publish failed; Windows ZIP `3,123,796,443` bytes, Android artifact около `1,789,476,336` bytes.
- **Причина:** GitHub ограничивает размер одного release asset; build success не гарантирует upload success.
- **Решение:** size-safe Windows update ZIP исключает updater-preserved runtime/model/cache directories; полный installer делится на части меньше 1900 MB с SHA-256 listing и PowerShell reassembler.
- **Профилактика:** preflight размера до release creation/upload; update package и full installer имеют разные контракты; test обязателен для updater-preserved directories.
- **Статус:** RESOLVED.

#### AF-MEM-075 — частично созданный draft после publish failure

- **Симптом:** draft release существует только с metadata/signature assets; повторный `gh release create` конфликтует.
- **Причина:** публикация не была идемпотентной.
- **Решение:** `gh release view`; создать только если нет; assets загружать через `gh release upload --clobber`; publish выполнять последним.
- **Профилактика:** draft-first transaction, re-runnable publish-only workflow.
- **Статус:** RESOLVED.

#### AF-MEM-076 — production publication завершена

- **Evidence:** Release run `35992779591`, job `publish` SUCCESS; download Windows/Android, layout normalization, size-safe assets, manifest, signature, draft update, evidence commit и final publish — все steps SUCCESS.
- **Verified product commit:** `c3693426e34d8c94b23b622a7050f7d78831beb7`.
- **Профилактика:** не удалять publish-only recovery path, size checks, idempotent draft update или signed evidence.
- **Статус:** RESOLVED; release published.

#### AF-MEM-077 — временный release/tag bootstrap оставил placeholder state

- **Симптом:** для запуска tag-bound release пришлось создавать временный prerelease, затем удалять placeholder, сохраняя tag; при ошибке мог остаться неполный release object.
- **Причина:** создание tag и GitHub Release было сцеплено с workflow publication.
- **Решение:** tag создавать отдельно и только после same-SHA RC; workflow работает draft-first и умеет продолжить существующий draft.
- **Профилактика:** preflight подтверждает отсутствие conflicting tag/release; create/update/publish — отдельные идемпотентные фазы.
- **Статус:** RESOLVED.

#### AF-MEM-078 — Windows reassembler всегда сообщал SHA mismatch

- **Симптом:** после объединения `part-00` и `part-01` скрипт удаляет готовый EXE и сообщает `Installer SHA-256 mismatch`, включая фактический hash.
- **Причина:** generated PowerShell содержал `-split '\\\\s+'` вместо `-split '\\s+'`. Regex искал literal backslash и не разделял строку `<hash>  <filename>`; `$expected` становился всей строкой.
- **Решение:** генерировать whitespace regex с одним backslash, извлекать первый 64-hex token и проверять reconstructed EXE; заменить только маленький release script asset, не части installer.
- **Профилактика:** static contract требует один backslash и отвергает double-backslash form; parser fixture проверяет строку формата `sha256sum`.
- **Evidence:** owner-PC actual hash `394bdb678f2d0c6deba82d2343ae34256c1e48d571364acbc993c55ae648a8e0`; root-cause fix `438c587f0ed38b1cd3ce94239e3211d3717f7ffa`.
- **Статус:** RESOLVED in source; published asset replacement required for V1.4.0.0.

### Network, downloads и CI stability

#### AF-MEM-080 — transient download/curl error 35

- **Симптом:** Godot/tool download sporadically fails.
- **Причина:** TLS/network instability.
- **Решение:** `--http1.1 --connect-timeout 30 --max-time 300 --retry 8 --retry-all-errors`, verified cache и ZIP integrity check.
- **Профилактика:** retry only idempotent downloads; hash before use.
- **Статус:** RESOLVED pattern.

#### AF-MEM-081 — retire branches/API timeout

- **Симптом:** `urllib` operation зависает/таймаутится при GitHub cleanup.
- **Причина:** отсутствовал bounded timeout/retry.
- **Решение:** explicit timeout + limited retries + resumable/idempotent operation.
- **Профилактика:** ни одного unbounded network call в release tooling.
- **Статус:** RESOLVED.

#### AF-MEM-082 — long run без progress/failure report

- **Симптом:** пользователь часами не понимает, работает ли build/emulator/import.
- **Причина:** silent waits и отсутствие phase heartbeat.
- **Решение:** каждая длительная фаза печатает start/progress/end, PID/path/report, bounded timeout; failure report создаётся даже при exception.
- **Профилактика:** это acceptance requirement для новых harnesses.
- **Статус:** INVARIANT.

#### AF-MEM-083 — недостаток диска на VPS/runner/owner PC

- **Симптом:** крупные model/Knowledge/APK/installer artifacts заполняют temp/workspace; REG.RU VPS исторически имел около 10 GiB диска.
- **Причина:** одновременно хранятся source, caches, unpacked runtime, staging и финальные archives.
- **Решение:** до build/import/publish вычислять требуемый запас; чистить только воспроизводимые caches/staging после hash/evidence; production data и private keys не удалять.
- **Профилактика:** disk-space preflight и отдельные staging directories; крупный Knowledge pack не помещать в Git history.
- **Статус:** INVARIANT.

#### AF-MEM-084 — разные shells/процессы не сохраняют локальные переменные

- **Симптом:** команда, отправленная следующей строкой/step, получает пустые `$sdk`, `$testRepo`, `$apk` или другой локальный state.
- **Причина:** каждый script line/CI step может выполняться в новом shell/process.
- **Решение:** передавать явные пути/arguments; в GitHub Actions использовать step outputs или `GITHUB_ENV`; owner-PC блоки запускать целиком в одной PowerShell session.
- **Профилактика:** инструкции помечают границы сессий; critical path не зависит от неэкспортированной переменной.
- **Статус:** INVARIANT.

## Проверенные опорные результаты

- Windows installed production Knowledge: `AURORA_WINDOWS_INSTALLED_PRODUCTION_KNOWLEDGE_OK`; offline; external AI not required; 60/60 shards; restart skipped 60; 75,871 records; 1,924,345,221 bytes.
- Signing secret preflight: Release run `35922892799` SUCCESS.
- Verified release candidate: `c3693426e34d8c94b23b622a7050f7d78831beb7`; Windows and Android package/device gates green.
- Production publish recovery: Release run `35992779591`, `publish` SUCCESS.
- Public release identity is committed; private updater key and Android keystore remain outside Git and backed up by owner.

## Шаблон новой записи

```markdown
#### AF-MEM-NNN — краткое имя

- **Дата/среда:** YYYY-MM-DD; OS/tool versions; exact SHA.
- **Симптом:** точный текст/код ошибки и наблюдаемое поведение.
- **Причина:** подтверждённая root cause; если не доказана — явно «гипотеза».
- **Нерабочие попытки:** только то, что важно не повторять.
- **Решение:** минимальный воспроизводимый fix/workaround.
- **Профилактика:** test/preflight/invariant, который не даст повторить ошибку.
- **Evidence:** commit, run/job/artifact/report без secret values.
- **Статус:** ACTIVE | RESOLVED | ENVIRONMENT | WAIVED | INVARIANT.
```

Новые записи добавляются по ID, существующие не удаляются ради «чистоты». Если причина уточнилась, старая формулировка сохраняется кратко в истории записи, а актуальная помечается датой. Дубли объединяются ссылкой на исходный ID.
