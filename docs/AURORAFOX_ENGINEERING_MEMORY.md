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

#### AF-MEM-079 — приложение отрицало собственный опубликованный release

- **Симптом:** установленная V1.4.0.0 сообщила, что релиз `Treninem/AI v1.4.0.0` не подтверждён, сослалась на старый HEAD `4c6fe649...` и baseline V1.3.0.0.
- **Причина:** ответ строился по stale internal/project knowledge или ненадёжному поиску GitHub вместо embedded signed build identity.
- **Решение:** сведения «какая версия установлена» читать из локальной встроенной version/release metadata; отдельно показывать последний проверенный signed update status. Сетевой поиск не является authority для self-identification.
- **Профилактика:** packaged offline smoke спрашивает версию и требует точное совпадение с canonical embedded version/commit; stale master-log/search text не может переопределить signed local metadata.
- **Evidence:** публичный release `v1.4.0.0`, commit `c3693426e34d8c94b23b622a7050f7d78831beb7`, publish run `35992779591` SUCCESS.
- **Статус:** ACTIVE for next product update; release itself is confirmed and stable.

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

#### AF-MEM-085 — Uvicorn crash в PyInstaller `--windowed` backend

- **Дата/среда:** 2026-09-24; установленная Windows AuroraFox V1.4.0.0; source HEAD `b667dd0ee43ed48e409829287eadd7c9436066ca`.
- **Симптом:** `aurora_voice_server` завершается до bind localhost: `AttributeError: 'NoneType' object has no attribute 'isatty'`, затем `ValueError: Unable to configure formatter 'default'` из `uvicorn.logging`.
- **Причина:** portable voice backend собирается PyInstaller с `--windowed`; в no-console процессе `sys.stdout`/`sys.stderr` могут быть `None`, а стандартный Uvicorn colour formatter определяет TTY через `isatty()`.
- **Нерабочие попытки:** перезапуск AuroraFox не исправляет детерминированную несовместимость logging configuration; ожидание chat response не восстанавливает упавший voice sidecar.
- **Решение:** запускать embedded Uvicorn без console-dependent default dictConfig: `log_config=None`, `access_log=False`, `use_colors=False`; voice failure не должен блокировать text Core.
- **Профилактика:** contract требует no-console-safe параметры; installed Windows smoke обязан запускать именно `AuroraVoiceBackend.exe` из `--windowed` сборки и проверять `/health`.
- **Evidence:** owner traceback; `voice/build_backend.ps1` содержит `--windowed`; source hotfix CLAIM `WORK-2026-09-24-V1.4-RUNTIME-RECOVERY-HOTFIX`.
- **Статус:** RESOLVED IN SOURCE; rebuilt installed-package acceptance pending.

#### AF-MEM-086 — обычный чат ошибочно проходит многовызовный agent pipeline

- **Дата/среда:** 2026-09-24; установленная Windows AuroraFox V1.4.0.0; owner request `привет` at 22:22:15, recovery notice at 22:25:56.
- **Симптом:** простой разговорный запрос ждёт минуты; после неудачи UI синхронно повторяет Core request и затем показывает recovery notice вместо ответа. Status `Готово • 45 инструментов • память 61` создаёт ложное впечатление готовой модели.
- **Причина:** подтверждённая source chain: AgentCore выполняет planning, answer и verification даже когда tool/action не требуется; desktop joined warmup допускает 120 секунд, chat request 180 секунд, а `main.gd` повторяет весь request после model error. Дополнительная resource-risk гипотеза до owner diagnostic: fixed context 16,384 повышает RAM/latency на consumer PC.
- **Нерабочие попытки:** ждать часами; повторять тот же запрос внутри одного UI submit; считать число зарегистрированных tools/memory доказательством готовности inference runtime.
- **Решение:** прямой one-call Core path для обычной беседы; immediate deterministic greeting while background warmup continues; no second synchronous retry; joined warmup 30 seconds; chat timeout 90 seconds; default context 4,096 with one parallel slot; direct chat caps output at 128 tokens and carries at most two compact memory hits plus four short history turns; honest recovery status. Complex/action requests retain planner/tools/verifier gates.
- **Профилактика:** focused contract limits direct conversation to one `ai.chat`, rejects planning/verification there, locks bounded waits and explicit status terminology. Add installed first-run conversational smoke before distributing hotfix.
- **Evidence:** owner screenshot/timestamps; owner hardware diagnostic: Pentium Gold G6405, 7.9 GiB RAM, model health OK after ~31 seconds at ctx 4096, prompt ~3.81 tok/s and generation ~3.06 tok/s; source inspection of `scripts/agent_core.gd`, `scripts/main.gd`, `scripts/desktop_local_runtime.gd`; focused direct tests pass without pytest runner.
- **Статус:** ACTIVE SOURCE FIX; owner hardware/runtime diagnostic and Windows package acceptance pending.

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

#### AF-MEM-087 — signed update floor confused with latest version ceiling

- **Дата/среда:** 2026-09-28; PR #96 head `9de9a81525df751e15baf7627f56c8a0f25b5d7f`, Release Identity CI `36353897008`.
- **Симптом:** `test_current_version_does_not_exceed_declared_signed_floor_before_release` rejects V1.4.1.1 because it asserts current <= 1.4.0.0.
- **Причина:** permanent signed update floor means minimum version with pinned signing trust, not a maximum current release version.
- **Нерабочие попытки:** changing permanent identity/floor to the new version would incorrectly break trust-floor history.
- **Решение:** assert current >= pinned floor and template floor equals public release identity; retain 1.4.0.0 as the permanent floor.
- **Профилактика:** release identity CI validates new versions against the permanent minimum without changing cryptographic identity.
- **Evidence:** failed job `108717681705`, 1 failed/22 passed; targeted test contract fix on release/v1.4.1.1.
- **Статус:** RESOLVED IN SOURCE; exact-SHA CI pending.

#### AF-MEM-088 — Windows updater displayed transport failure as HTTP 0 and discarded long transfers

- **Дата/среда:** 2026-09-28; installed Windows V1.4.0.0/V1.4.1.1; source base `caba7d34eb497e6a25b37a61d300f1cd6fb029cd`.
- **Симптом:** updater reported server code 0; two roughly 1.999 GB Windows transfers ended after about 1800 seconds and restarted from zero.
- **Причина:** transport result and HTTP response code were conflated; the legacy whole-file `HTTPRequest` also used a fixed 1800-second timeout and removed the partial package on failure.
- **Нерабочие попытки:** treating 0 as an HTTP status; blindly pressing retry; only increasing the whole-file timeout to 1–3 hours. A larger timeout still loses progress after an interruption.
- **Решение:** distinguish Godot transport result from HTTP status, retry signed metadata with GitHub API fallback, and supersede whole-file delivery with the AF-MEM-090 part contract.
- **Профилактика:** update smoke distinguishes TLS/connect/timeout from HTTP status and guards the resumable signed-part path.
- **Evidence:** owner updater log times; PR #97 source; consolidated V1.5 candidate tests.
- **Статус:** RESOLVED IN CONSOLIDATED SOURCE; installed acceptance pending.

#### AF-MEM-089 — Settings PopupPanel closes on outside click; full chat redraw stalls presentation

- **Дата/среда:** 2026-09-28; owner Windows/Android V1.4.0.0/V1.4.1.1; source main `caba7d34eb497e6a25b37a61d300f1cd6fb029cd`.
- **Симптом:** Settings hides on outside click; Android can announce completion while the live chat does not present the result until restart.
- **Причина:** confirmed source costs: desktop Settings used outside-dismiss `PopupPanel`; every append/resize rebuilt all message controls; `ChatStore.add_message()` synchronously serialized and rewrote the full history before the caller could render.
- **Решение:** desktop non-transient native `Window`; mobile PopupPanel retained; settings paints before health probes; append only new cards; resize only refits widths; message persistence is deferred to the next idle turn and uses a temporary file before replacement.
- **Профилактика:** UI smoke asserts desktop/mobile window classes and old-card identity; persistence contract requires deferred append; installed Windows taskbar and Android same-session evidence remain mandatory.
- **Evidence:** Godot 4.7.1 `AURORA_DESKTOP_AND_MOBILE_UI_SMOKE_OK`, `AURORA_WORK_MODE_SMOKE_OK`; source candidate based on PR #98.
- **Статус:** RESOLVED IN SOURCE CANDIDATE; packaged/device/visual acceptance pending.

#### AF-MEM-090 — durable signed-part updater for interrupted networks

- **Дата/среда:** 2026-09-29; consolidated V1.5 platform candidate from exact main `de1313f8ef53be7fa8092823d3ef5980b9702d75`.
- **Симптом:** a multi-gigabyte update could lose all downloaded bytes after timeout, connection loss, application restart or OS restart.
- **Причина:** one monolithic HTTP request and one temporary destination had no durable verified checkpoints.
- **Решение:** signed schema-v2 manifest keeps the backward-compatible whole asset and adds ordered 64 MiB parts with URL/size/SHA-256. The client verifies and retains each completed part, resumes a partial current part with HTTP Range plus validated Content-Range, retries stalled/missing parts with bounded backoff but no total update deadline, streams assembly, then verifies the whole-package SHA-256 before existing atomic apply/health/rollback.
- **Профилактика:** reject traversal/duplicate names, non-HTTPS URLs, invalid hashes, oversized parts and aggregate-size mismatch; signed manifest generation asserts part counts/sizes and release uploads every declared part.
- **Evidence:** Godot 4.7.1 update smoke `AURORA_UPDATE_GODOT_SMOKE_OK automatic=true resumable_parts=true`; five focused Python contracts pass; GDScript fixture reuses verified part and assembles in signed order.
- **Статус:** SOURCE ACCEPTED LOCALLY; exact-SHA CI, real interrupted transfer and installed Windows/Android acceptance pending.

#### AF-MEM-091 — архив принимался как Knowledge без чтения содержимого

- **Дата/среда:** 2026-09-30; fresh main `446ce2cd2f979a8ab228f63d090062e8ba48a6eb`; owner case `files (2).zip` + команда `изучи`; source fix `6dcf015`.
- **Симптом:** AuroraFox могла сообщить об импорте ZIP/7z/tar в Knowledge, хотя в базу попадал только перечень имён и размеров файлов; реальные TXT/JSON/JSONL/CSV и другие текстовые данные внутри ZIP не читались.
- **Причина:** `file_service._archive_listing()` формировал только listing, а `AttachmentManager._import_extracted_knowledge()` принимал любой непустой ответ File Intelligence за извлечённый текст.
- **Нерабочие попытки:** повторно выбирать архив; переименовывать его в `knowledge*.zip`; повторять `изучи`. Это меняло классификацию, но не добавляло отсутствующее извлечение содержимого.
- **Решение:** ZIP/tar reader потоково читает только разрешённые текстовые расширения с отдельными лимитами member/total/output; JSONL/NDJSON стали first-class text; unsafe paths и бинарное содержимое не читаются; превышение declared expanded budget блокирует всё content extraction. AttachmentManager импортирует архив только при `text_entries_extracted > 0`, иначе возвращает честную ошибку. 7z остаётся listing-only до появления безопасного bounded reader и не выдаётся за успешный Knowledge import.
- **Профилактика:** fixture с нейтральным `files (2).zip` требует реальные TXT/JSONL facts, исключает `../escape.txt`, проверяет zip-bomb budget и строгий output cap; Godot smoke использует нейтральное имя и доказывает, что Knowledge import начинается только после явной команды `изучи`.
- **Evidence:** source commit `6dcf015`; `AURORA_ARCHIVE_TEXT_EXTRACTION_OK`; `AURORA_ARCHIVE_BOMB_BUDGET_OK`; `AURORA_CHAT_LEARNING_ATTACHMENT_OK`; `AURORA_DESKTOP_AND_MOBILE_UI_SMOKE_OK`; 31 focused P0 contracts PASS; exact-SHA CI pending.
- **Статус:** RESOLVED IN SOURCE; GitHub CI and installed Windows archive acceptance pending.

#### AF-MEM-092 — API feedback существовал без feedback-контролов основного чата

- **Дата/среда:** 2026-09-30; local branch `fix/v1.5-archive-knowledge-import`; implementation commit `6661c4c`.
- **Симптом:** API принимал `/v1/feedback`, но ответы основного Windows/Android чата не имели `+ / −`; пользователь не мог связать оценку с точным локальным ответом или безопасно подтвердить обучение на ней.
- **Причина:** feedback transport/storage был реализован только для API learning sync; `ChatStore` не имел стабильных message IDs/feedback metadata, а message cards не создавали controls.
- **Нерабочие попытки:** считать API endpoint доказательством готового клиентского UX; автоматически писать положительный/отрицательный feedback в память или веса без owner review.
- **Решение:** стабильная message identity + runtime/model/version metadata; компактные доступные `+ / −`; локальный Core готовит только bounded analysis proposal; owner ConfirmationDialog отдельно разрешает private ExperienceStore write. Изменение/отмена оценки отзывает ранее подтверждённый feedback experience. Веса/shared Core не меняются.
- **Профилактика:** Godot runtime smoke проверяет exact prompt/answer identity, proposal state и retraction; UI smoke требует controls под каждым assistant answer; static contract запрещает memory/experience mutation внутри analysis function до подтверждения.
- **Evidence:** `AURORA_CHAT_FEEDBACK_OK`; `AURORA_DESKTOP_AND_MOBILE_UI_SMOKE_OK`; 3 focused Python contracts PASS; exact-SHA remote CI pending.
- **Статус:** RESOLVED IN LOCAL SOURCE; publication/package/device acceptance pending.

#### AF-MEM-093 — имя файла и embedded manifest молча разрешали durable learning

- **Дата/среда:** 2026-09-30; local implementation commit `766dacd`.
- **Симптом:** файл с именем `training*.jsonl`, `skills*.jsonl` или knowledge-like payload мог импортироваться при выборе без явной команды пользователя; короткий список фраз не покрывал естественные перефразировки.
- **Причина:** `AttachmentManager._learning_type()` использовал instruction, затем filename, затем payload как равноправные источники разрешения на durable write.
- **Нерабочие попытки:** бесконечно расширять один список exact phrases; считать filename/payload пользовательским подтверждением; смешивать `прочитай/расскажи/посчитай` с `сохрани/изучи`.
- **Решение:** отдельный `UserIntentRouter` нормализует русские/английские перефразировки, negation, capability questions, knowledge/training/skill targets. Durable import разрешается только submitted instruction; filename/manifest остаются untrusted classification data и сами не дают write authority. Неясный запрос остаётся analyze-only.
- **Профилактика:** runtime matrix покрывает `изучи/усвой/запомни/внеси/можешь изучить`, training/skill variants, `не изучай`, `прочитай и расскажи`, capability/how-to questions и calculation requests.
- **Evidence:** `AURORA_USER_INTENT_ROUTER_OK`; `AURORA_CHAT_LEARNING_ATTACHMENT_OK`; 2 focused Python contracts PASS; exact-SHA remote CI pending.
- **Статус:** RESOLVED IN LOCAL SOURCE; publication/package/device acceptance pending.

#### AF-MEM-094 — generic `http_get` allowed unsafe destinations and raw-page false learning

- **Дата/среда:** 2026-09-30; local continuation after exact remote tree `8ad6044`.
- **Симптом:** Core имел generic `http_get`, который принимал любой HTTP(S) URL, автоматически следовал redirect, не проверял DNS/private/link-local адреса, не ограничивал тело через `body_size_limit`, возвращал сырой HTML и не связывал чтение с provenance/Knowledge. Ответ по ссылке мог выглядеть как «изучение» без доказуемого сохранения.
- **Причина:** инструмент создавался как ранний универсальный fetch helper и не проходил отдельный untrusted-web/SSRF/access-control design.
- **Нерабочие попытки:** считать проверку префикса `http://`/`https://` достаточной; полагаться на модель для выбора безопасного URL; принимать HTTP 3xx как успех без повторной валидации назначения.
- **Решение:** единый `PublicWebManager`: проверка схемы/credentials/DNS и всех resolved addresses, повторная проверка каждого redirect, bounded timeout/body/redirects, type-aware text extraction без script/style, CAPTCHA/login/access-control reporting, provenance SHA-256 и private Knowledge import. Compatibility `http_get` использует тот же reader.
- **Профилактика:** runtime smoke для loopback/metadata/private IPv4/IPv6/nonstandard public port/HTML stripping/owner decision; static contract запрещает отдельный сырой HTTPRequest в `http_get`.
- **Evidence:** `AURORA_PUBLIC_WEB_MANAGER_OK`; `AURORA_PUBLIC_WEB_CONTRACT_OK tests=4`; exact-SHA CI pending.
- **Статус:** RESOLVED IN LOCAL SOURCE; remote/package/device acceptance pending.

#### AF-MEM-095 — read/analyze intent contradicted owner knowledge contract

- **Дата/среда:** 2026-09-30; owner clarification «прочитать и запомнить — одно и то же».
- **Симптом:** `UserIntentRouter` специально классифицировал `прочитай/расскажи/посчитай` как analyze-only, поэтому реально прочитанный пользовательский файл мог не сохраниться в Knowledge; веб-источник мог дублироваться целиком в task memory и раздувать следующие prompts.
- **Причина:** прежняя policy считала durable write допустимым только при отдельном глаголе `изучи/запомни`, что не соответствовало уточнённой модели владельца.
- **Решение:** чтение/анализ/расчёт/поиск в пользовательском источнике разрешает private Knowledge import с provenance; явное отрицание по-прежнему отменяет сохранение. Веб-страница сохраняется полностью chunked в Knowledge, а Core получает до 24k релевантных фрагментов; user-task trace отдельно ограничен 12k и не дублирует весь источник.
- **Профилактика:** semantic intent runtime matrix включает read/calculate/find как Knowledge и оставляет negation/capability questions non-persistent; owner-control audit отмечает prompt/memory пределы как отдельную policy.
- **Evidence:** `AURORA_USER_INTENT_ROUTER_OK`; `AURORA_CHAT_LEARNING_ATTACHMENT_OK`; six focused intent/web contracts PASS.
- **Статус:** RESOLVED IN LOCAL SOURCE; remote/package/device acceptance pending.

#### AF-MEM-096 — exact-SHA CI contracts pinned obsolete call spelling

- **Дата/среда:** 2026-09-30; PR #103 head `783b46eec6e0409c3d25470fd1f3fa1559f2adfe`; runs `36717626031` and `36717625933`.
- **Симптом:** Core Benchmarks failed 1/31 although Godot Core runtime passed; Core/Voice Python failed 1/70 while its File Intelligence, Windows integration and Godot Core jobs passed.
- **Причина:** tests pinned implementation spelling/location, not behavior: one searched the obsolete two-argument substring `chats.add_message("assistant", answer)` after response metadata was added; another demanded both `_learning_type_from_instruction(question)` and the literal `"изучи"` inside AttachmentManager even though semantic phrases had intentionally moved into `UserIntentRouter`.
- **Нерабочие попытки:** rerun unchanged jobs; interpret these two assertion errors as model/runtime regressions.
- **Решение:** ordering contract matches the stable call prefix regardless of added metadata; AttachmentManager routes through its compatibility helper again; the intent contract validates the router call and semantic patterns in `UserIntentRouter`, preserving filename/payload authority boundaries.
- **Профилактика:** source contracts assert externally relevant order/route invariants and tolerate compatible argument additions; exact failed suites are rerun locally before publishing the correction.
- **Evidence:** PR #103 runs/jobs `36717626031/109894376434` and `36717625933/109894376571`; corrected exact suites pending.
- **Статус:** ROOT CAUSE FIXED LOCALLY; exact-SHA rerun pending.


#### AF-MEM-097 — binary URL responses were decoded/rejected before File Intelligence

- **Environment:** continuation of PR #103 exact baseline `7c05eee0a673c86bf3289d01e4113db00ff156fb`, 2026-10-01.
- **Symptom/root cause:** PDF/Office/image/archive URLs failed `unsupported_content_type`; HTTPRequest response bytes were unconditionally decoded as UTF-8. URL flow also ignored explicit no-save instructions despite router support.
- **Fix:** keep PackedByteArray; select parser using signature/MIME/URL/disposition and Office/EPUB ZIP member identities; private random staging path; invoke existing FileIntelligenceClient; delete staging on successful/failed results; reject binary descriptions and archive listings as Knowledge. Honor router negation and report omitted URLs rather than silently slicing them. Raw download hash and extracted-text hash are distinct provenance fields.
- **Prevention/evidence:** `tests/public_document_url_smoke.gd` executes staging, byte identity, cleanup, actual Knowledge import/query, no-save, generic ZIP→DOCX selection, archive listing/backend failure, CAPTCHA and owner-limit cases with explicitly substituted transport/parser responses. It proves routing/storage boundaries, not real parser/platform capability. Existing remote File Intelligence parser and Windows/Android package gates remain required. Extraction cap is visible in Settings; downstream parser ceilings remain inventory findings.
- **Status:** LOCAL ROUTING/STORAGE ACCEPTED; exact-SHA remote parser/package/device acceptance pending.

#### AF-MEM-098 — truncated cached Godot binary segfaulted before startup

- **Environment:** local `.ci/godot-local/Godot_v4.7.1-stable_linux.x86_64`, 2026-10-01.
- **Symptom:** immediate segmentation fault with empty log even before version/project parsing.
- **Root cause/evidence:** ELF file had missing section headers and only ~87 MiB; ZIP entry declared 144,583,504 bytes. ZIP CRC test passed.
- **Fix:** re-extract verified archive to separate scratch directory; recovered executable reports `4.7.1.stable.official.a13da4feb` and parses/runs project smokes. Do not change product source or weaken tests for this environment defect.
- **Prevention:** validate archive CRC, extracted byte count and `--version` before parser diagnosis.
- **Status:** RESOLVED ENVIRONMENT.


#### AF-MEM-099 — failed security retest must not imply remediation

- **Environment:** authorized security workspace local foundation, 2026-10-01; parent `a38455196489fdcfcfdde627e9eca00ab7f8b4f4`.
- **Invariant:** target/scope/time authorization is required before traffic; source documents never grant execution permission. Header/cookie configuration checks cannot establish successful exploitation or a whole-system security grade.
- **Prevention:** exact origin/URL preflight, private-lab explicit opt-in, rechecked expiry, public DNS address validation and pinned socket, validated TLS, no redirects/auth bypass; bounded body/time/request budgets; redacted evidence; retest only same scope and successfully checked targets. Transport/access failure yields `retest_inconclusive`, never resolved.
- **Evidence:** four `unittest` local HTTP lab cases PASS: actual vulnerable→fixed remediation/retest; denied/expired/out-of-scope/private target produces zero requests; redirect/access boundary; changed scope and failed retest plus body/cookie/query/error redaction. Runner not yet integrated into Core/chat; no external target executed.
- **Status:** LOCAL CONFIGURATION-CHECK FOUNDATION ACCEPTED; broader authorized test tools/chat integration and live target evidence pending.


#### AF-MEM-100 — parser/web operational ceilings were adjustable only outside the product UI

- **Дата/среда:** 2026-10-01; PR #103 continuation after security HEAD 3626fb13d1f1ca8d02e706be3b80d7786471d56b reached 24/24 green checks.
- **Симптом:** File Intelligence environment budgets existed, but the owner had to edit process environment values manually; public URL length/title/relevant-context ceilings remained source literals.
- **Корень:** settings exposed only public download/extraction/time limits; FileIntelligenceClient did not persist/export parser budgets and still clamped one request at 500000 characters.
- **Исправление:** persisted `aurorafox/files/*` owner settings; environment export before backend start/restart; visible Files settings card; owner-controlled request text ceiling in Python health/schema; public URL/title/context controls exposed and persisted.
- **Профилактика:** `test_owner_runtime_limits_contract.py` rejects reintroduction of the fixed 500000/4096/400/24000 ceilings and requires owner UI plus propagation markers. Inventory remains incomplete until unrelated findings are classified.
- **Статус:** SOURCE IMPLEMENTED; exact-SHA CI pending for this new commit.


#### AF-MEM-101 — fixed-value CI assertion outlived an owner-controlled runtime budget

- **Дата/среда:** 2026-10-01; PR #103 HEAD `cb85b54ef88c1b4d5df561f301368c881667de72`; Chat Learning job `110338029520`.
- **Симптом:** source contract failed although the changed behavior was intentional: `PublicWebManager` no longer contained literal `.substr(0, 24000)`.
- **Корень:** an older contract asserted the implementation literal rather than the invariant. The relevant-context budget had been promoted to owner-visible `context_chars`, so preserving the old assertion would force an unwanted hidden product ceiling back into source.
- **Исправление:** contract now asserts dynamic `.substr(0, context_chars)` plus owner-limit exposure; cheap Chat Learning preflight also executes owner-runtime-limit/security-tool contracts.
- **Профилактика:** tests for operational limits must assert ownership, persistence and propagation, not a frozen default value. Defaults may remain documented but cannot masquerade as hard boundaries.
- **Статус:** FIX PREPARED; exact-SHA remote CI pending.

#### AF-MEM-102 — standalone security runner was not reachable from installed chat tools

- **Дата/среда:** 2026-10-01; continuation of AF-MEM-099.
- **Симптом:** the authorized configuration runner and real remediation/retest lab existed, but the normal Windows ToolRegistry could not invoke the same audited runner and the installer did not place it beside a callable Python runtime.
- **Корень:** security foundation intentionally stopped before product integration; no private-path bridge/package contract existed.
- **Исправление:** dedicated `security_configuration_check` tool requires separate explicit authorization, canonical private `user://` scope/baseline/output paths, launches the exact runner asynchronously with the bundled File Intelligence Python, and returns only redacted evidence. Build copies the exact runner; Windows CI requires the packaged file.
- **Профилактика:** source contract rejects missing authorization/private-path/process/package markers. Scope content alone never authorizes execution; redirects/auth/access controls remain boundaries; failed or absent evidence cannot be called success.
- **Статус:** SOURCE INTEGRATION PREPARED; exact-SHA parse/package/tool contracts pending.


#### AF-MEM-103 — model authorization flag and mutable private evidence paths are not owner consent

- **Environment:** 2026-10-05, inherited Windows bridge at `a15e065e9286009e10dc297f5360f9d360633127`; prior exact SHA 30/30 checks green did not cover this authority defect.
- **Confirmed source defects:** model-controlled `authorized=true` reached a network-capable child without a trusted UI review; arbitrary user:// output was deleted before launch; empty results could report success. AF-MEM-102's assertion of separate authorization must be read with this correction.
- **Fix:** flag requests review only. Main UI supplies a trusted callback and full exact-scope dialog, fail closed without that callback or on refusal; re-read scope/baseline after approval and reject changed bytes. Snapshot reviewed bytes into a cryptographically random reserved run directory; generic file tools deny writes there. Reject custom output paths, never remove an existing file. Reject lexical escape and symlink traversal. Runner CLI includes exact input-file SHA-256; bridge binds schema, byte hash, target count/order/hashes and nonempty outcomes.
- **Master stop:** pass AgentCore execution guard into the security bridge; re-check before child launch and while polling, kill on denial and on registry shutdown, return stopped rather than successful evidence.
- **Evidence:** headless Godot runtime regression proves callback absence, refusal, approved exact bytes, scope mutation, reserved paths/traversal/no overwrite, malformed/empty/wrong-scope/non-checked evidence and guard denial. Five stdlib tests use a real loopback server, including actual CLI subprocess input hash, findings/remediation/retest and access boundaries. These tests do not claim physical Windows UI acceptance.
- **Prevention:** never promote a model parameter, imported file or document to owner authorization. Scope acceptance is not permission to overwrite unrelated state. Success requires actual complete evidence bound to the reviewed inputs.
- **Status:** local runtime/real lab PASS; new exact-SHA CI and physical Windows dialog acceptance remain separate gates.


#### AF-MEM-104 — passing a cancellation guard invalidated an exact two-argument source assertion

- **Environment/evidence:** `4da2043`, Core gate-contract job `111635245148`: 1 failed / 30 passed; failure at test_core_specialist_team_runtime_contract.py:89, ValueError substring not found.
- **Root cause:** source assertion demanded `tools.call_tool(tool_name, args)` while production now correctly passes a third `execution_guard` to keep master stop active during asynchronous security execution. This is an assertion migration, not evidence that tool argument repair stopped working.
- **Fix/prevention:** require guarded call and retain the ordering assertion that structural repair precedes execution. Search all contracts for the old call spelling when changing the tool ABI. Never restore the unguarded call merely to satisfy CI.
- **Status:** local source contract PASS; exact new-head CI pending.


#### AF-MEM-105 — optional Work guard cannot be the only global master-stop check

- **Confirmed:** ordinary main chat invokes AgentCore without the optional Work guard. Guard propagation alone therefore protects Work cancellation but is insufficient to assert global master-stop coverage for all entry points.
- **Fix:** independently query ComputerClient.master_enabled_from(self) before child launch and throughout asynchronous waiting, before treating completion as evidence. Keep optional guard as an additional denial authority. Remove custom output_path from catalog rather than induce model attempts to use a forbidden output path.
- **Runtime evidence:** Linux headless smoke creates actual child processes and independently verifies they no longer exist after global master stop or execution guard denial. After Godot OS.kill, calling OS.is_process_running on the reaped PID emits an engine error; use external /bin/kill -0 solely in the regression to verify actual OS liveness cleanly.
- **Status:** local lifecycle/owner-review smoke and source contracts PASS; physical Windows behavior remains a device gate.


#### AF-MEM-106 — spreadsheet extraction ceilings must be owned, observable and part of cache identity

- **Confirmed at 3037cb3:** XLS/XLSX used fixed 50,000-cell cutoffs, XLS additionally iterated only 10,000 rows with no omission warning. Whole-row accounting could exceed the stated cell ceiling. Parser cache keys omitted these resource settings, so exposing them without cache invalidation could keep serving an old truncated result.
- **Fix:** preserve defaults as AURORAFOX_FILE_SPREADSHEET_MAX_CELLS and AURORAFOX_FILE_XLS_MAX_ROWS, visible/persisted/exported by Settings and FileIntelligenceClient. Exact cell clipping across sheets, XLS rows_read, output_truncated, truncation_reasons, actual budgets and actionable warnings; the service already propagates metadata.output_truncated. Include both owner budgets and a new schema salt in cache identity. No new row cap introduced for XLSX.
- **Evidence:** six isolated production-function tests run real openpyxl/xlrd on genuine XLSX and BIFF2 XLS data, including 50,001 XLSX cells, 10,001 XLS rows, partial-row/global-cell bounds, exact-fit nontruncation and actual cache keys. AST function isolation loads exact production definitions without mocking parser libraries or faking absent requests/FastAPI. A separate full-service cache/truncation regression is wired into File Intelligence CI; it is NOT executed locally because real API dependencies are unavailable. Headless Godot proves values above the former ceilings reach ProjectSettings and actual backend environment; integrated parse/source contracts PASS.
- **Prevention:** do not call extraction complete just because a parser returned text; propagate omission status to public-link retention. Changing an owner budget must change cache identity whenever it can affect extracted content. Parser unit evidence is not full API or physical device acceptance.
- **Status:** local parser/settings tests PASS; full-service/exact-head remote CI pending.


#### AF-MEM-107 — listing/search limits, omitted defaults and stale local Godot cache

- **Confirmed at c67507e:** Windows tree bound remained 5000, search bound 100 and cache excerpt 1200. Tree marked exact-fit responses truncated. Pydantic omitted defaults can exceed an owner-lowered ceiling unless default is min(original_default, owner_ceiling).
- **Prepared fix:** persisted/exported Windows tree/search/excerpt controls; exact tree overflow evidence via one additional valid item. Preserve search early stop and return limit_reached plus more_results=unknown, rather than scan the remaining cache or claim unverified omission. Excerpt truncation is directly measured. Bound omitted schema defaults by actual owner ceilings. Android native tree/parser ceilings remain unfinished and are not declared owner-controlled.
- **Local evidence:** four tests run exact production function bodies over real directories and JSON cache, including 5001 files, 101 matches, >1200-char excerpts, exact fit/overflow and malformed cache entries. Owner contracts PASS. Full-service environment/schema regression is prepared for CI; absent API dependencies are not faked.
- **Local engine blocker:** earlier /tmp verified Godot was absent. Revalidation rejected .ci/godot-local/godot.zip with BadZipFile: 57,203,200 bytes, SHA256 e59ea78fede63c7c6f3f558bde6f181ffec19ed6dbe7e50b1bb8229cba24a6ec; cached ELF 90,524,160 bytes is shorter than known 144,583,504 bytes. Cause of cache truncation is not established. Neither corrupt ELF nor invalid ZIP is accepted as a runtime. New Godot parse/settings smoke is NOT EXECUTED; verify a complete fresh runtime or use next exact-SHA CI after owner reports current checks. This extends AF-MEM-098; no repeated repair/download loop.
- **Status:** local filesystem/cache/contracts PASS; SOURCE PREPARED, unpushed while current CI runs; new Godot/full-service acceptance pending.


#### AF-MEM-108 — archive listing allocation and headers must honor owner budgets

- **Confirmed at 8187d3a:** archive listing had a hidden quarter-of-output/40000-character ceiling; archive owner limits were absent from parser cache identity. On tiny output budgets the listing header exceeded the entire budget, and a clipped extracted-file header could count as learned content without any payload.
- **Fix:** expose persisted/exported listing character cap and percentage, preserve 40000/25% defaults, permit zero to hide listing while retaining file content. Percent 0–100 expresses the share of the request rather than a second absolute ceiling. Include every archive extraction/allocation budget in cache identity. Bound listing headers by request size; content count requires room beyond the complete extracted-file header. Separate listing/content truncation metadata and actionable content warning.
- **Evidence:** five exact production-function regressions over genuine ZIP/tar data cover raised >40000 output, disabled listing with retained text and unsafe-path exclusion, tiny/header budgets, exact fit/content omission and each cache-setting invalidation. Six spreadsheet and four filesystem/cache regressions remain PASS; source owner contracts PASS. Godot settings/environment smoke extended; not executed locally because AF-MEM-107 runtime defect persists, full API/Godot acceptance belongs to new-head CI.
- **Prevention:** include all extraction-changing settings in cache identity; count payload, not only parser headers, as extracted information. Always measure total emitted characters including formatting.
- **Status:** local archive/regression unit evidence PASS; full API, Godot and physical acceptance separate.


#### AF-MEM-107 continuation — Android tree budget propagation

- Native tree and its Godot caller each imposed 5000 regardless of the persisted owner ceiling, and native response did not identify truncation. Local preparation passes the existing tree_max_items setting, uses a pure Kotlin boundedDirectoryTree helper and observes one next actual file to distinguish exact fit from overflow. Private-root authorization unchanged.
- Three JUnit cases use actual filesystem directories, including 5001 files, exact fit/overflow, empty/minimum budgets. Kotlin/compiler/Gradle are unavailable locally; these cases are NOT EXECUTED locally and require Android Plugin CI. Source propagation contract PASS is a separate limited evidence type. Full Android parser/OCR budgets remain unfinished.


#### AF-MEM-109 — Core long-context empty response needs actual error evidence

- **Confirmed:** 3d96ed429bd9c3150454e6c443f9b8f8e5107595, run37333751554/job111843252931, Core real benchmark fails only long_context (20/21 PASS). Prompt12841 chars;90068.494ms; empty content/zero completion tokens; runtime wrapper aurora_core. Offline CodeSpecialist PASS; hard performance PASS; baseline comparison not applied because CPU/runtime identity differ (not a relative regression). File Intelligence/parser gates green.
- **Cause:** not established. ~90-second timing is consistent with a request deadline but does not prove the underlying transport/inference cause. Core source unchanged from green8187d3a; a one-job same-SHA repeat isolates reproducibility without modifying quality gates or restarting Windows packaging.
- **Evidence gap:** _chat_row stores output/runtime but drops result.ok/error/attempted_models/failure_scope. No stderr failure and no actual runtime error in uploaded benchmark artifact11355856840 (zip SHA256077c6db5e8b6bcb8deab148d53b546ce2836d0027587cccde3eef481a14f3653). Do not infer a parser regression or count the repeat as PASS before completed evidence.
- **Action/prevention:** one targeted real-core-windows rerun requested; no retry loop, timeout increase, scenario reduction or policy relaxation. If reproducible, preserve bounded runtime error fields in benchmark report before product diagnosis; no speculative Core change.
- **Status:** unresolved, exact same-SHA rerun pending.


#### AF-MEM-109 repeat result — same-SHA Core gate succeeds

- One targeted repeat on unchanged3d96ed429bd9c3150454e6c443f9b8f8e5107595 completed SUCCESS; all30 exact-SHA check-runs now SUCCESS. No product/benchmark change, timeout increase, gate relaxation or additional repeat performed.
- Original long-context failure is NOT REPRODUCED on this repeat; root cause remains unknown, not labelled a confirmed infrastructure defect. Preserve original artifact/job and missing-error-report lesson for a future recurrence. Repeat success validates this acceptance run but does not establish why the first run failed.


#### AF-MEM-110 — Android parsers ignored owner settings and ZIP retained only listing

- **Confirmed source at9ffdaa2:** native parsers imposed160000 output chars/50000 cells, file1GiB and OCR128MiB/200PDF/150OCR limits without reading persisted settings. Office XML/text used whole-stream readBytes; non-OCR parsers ran on the Godot UI call. ZIP returned only a listing, not extracted Knowledge. Native output/header clipping could leave no actual source payload.
- **Owner decision:** platform defaults were explicitly discussed; owner delegated best maximum-capability choice. Prepared common visible owner defaults matching current Windows PDF256MiB/1000pages/500OCR, independently adjustable on each installed device. This is a deliberate default increase, not a claim old Android defaults were retained.
- **Prepared fix:** immutable FileAnalysisLimits JSON snapshot captured before queue submission; all Android file analyses use existing async job/poll/cancel mechanism, legacy native methods preserved. Bounded actual stream read with one-byte overflow probe; XML/member-byte limit and rejection of DTD/entity declarations even if Android factory lacks disable flags. Shared requested output/cell/file/archive/PDF/OCR/input/render budgets; deadline and pending-job count visible Settings. Store actual per-job limits and explicit truncation; exact cell fit is not falsely omitted. XML parser and render arithmetic never promote imported data to authority.
- **ZIP:** read allowed text/JSONL members without filesystem extraction; reject absolute/drive/traversal and binary content; expanded/member/total/output budgets, real text_entries_extracted and bytes read vs retained metadata. Tiny budgets cannot retain only a header as knowledge. Unsupported XLS/7z/rar/tar/EPUB native formats remain explicitly unfinished; this block does not claim their implementations.
- **Evidence:** existing Android contract and15 source/inventory contracts PASS;5 genuine ZIP/tar and4 filesystem/cache Python regressions PASS for Windows production functions. Ten new JVM cases use immutable snapshots, actual byte streams/cancellation, genuine ZIP content/unsafe names/raised>160000 output/exact entry limits/blocked expanded size, header/output budgets, render geometry and UTF8/UTF16 XML-declaration guards. JVM cases are NOT EXECUTED locally: Kotlin/Gradle absent; Godot runtime also unavailable perAF-MEM-107. New-head Android Plugin/JUnit/Godot/package/device gates mandatory after publication; source contracts do not replace them.
- **Prevention/status:** settings are per job, never mutable shared parser state; count actual payload, use bounded reads, report omission. SOURCE PREPARED LOCALLY, not accepted as installed Android behavior until runtime evidence.


#### AF-MEM-109 recurrence — require transport and backend diagnostics instead of blind repeats

- **Confirmed second occurrence:**9ffdaa2527a23d8d66276297878c0800f2008e9c, run37350313139/job111899302623/artifact11363275188. Same long_context empty/zero completion tokens after90034.443ms;20/21quality, performance hardPASS. One prior green repeat is insufficient to call this resolved. Actual runtime error still absent from old report; no stdout/stderr explanation.
- **Prepared diagnosis:** benchmark row includes bounded explicit error/scope/runtime/HTTP/transport/retry flags and up to3 sanitized attempt records, excludes raw/prompt/model-path dictionaries. Wrapper preserves existing HTTP/transport fields. Benchmark-only environment opts in llama-server --log-file, runner and artifact workflow collect its engine log; normal chat does not enable the file log. Flag verified against official ggml-org/llama.cpp7fe450e19/common/arg.cpp. Deterministic Godot smoke checks bounded fields, transport13/http0, omitted private fields, success state; new-head CI required, not locally executed.
- **Validation/status:**16 actual evaluator/source contractsPASS locally. No scenario/quality/runtime/deadline relaxation and no speculative inference fix. Source package combined with already prepared Android controls to avoid two successive full builds. Root cause remains unresolved pending exact new-head report/logs; do not restart again blindly.


#### AF-MEM-110 validation reconciliation

- Native immutable owner controls, bounded Office XML/ZIP and shared async execution compiled and passed the ten genuine JVM regressions in the exact9e72afa Android Plugin gate. All35 starting-SHA checks succeeded. This supersedes SOURCE PREPARED for that source package; installed physical-device acceptance remains separate.

#### AF-MEM-111 — EPUB/tar must be parsed as content, with internal references bounded

- **Confirmed source:**9e72afa native dispatch sent EPUB/tar/tgz/tar.gz to unknown binary/text fallback despite existing JVM XML and Commons Compress dependencies. This could not recover chapter/archive knowledge. No new dependency is needed for these formats.
- **Fix:** EPUB container→OPF manifest→spine order, internal URI resolution with root-stack validation before normalization (normalization alone can obscure attempted root escape), bounded XML plus explicit DTD/entity rejection; iterative visible DOM text skips head/script/style. Empty/external/absolute spine references are rejected, never fetched. Tar/gzip streams extract allowed text without writing members; traversal/drive/absolute/link records skipped, sparse records rejected. Saturating size arithmetic includes non-directory payloads, including skipped unsafe members. Decompressed stream also bounded during Commons internal PAX/GNU parsing: owner expanded bytes plus owner-entry header allowance (1024bytes per entry,10KiB final tar record padding), with interruption checks and bounded skip.
- **Prevention:** six genuine JVM fixture tests cover spine order/metadata/UTF8/active content, external/escape/empty paths, output/member/entry limits, real tar and gzip extraction, unsafe records, exact/overflow entry count, expanded-size rejection and payload-vs-header counts. Shared ZIP decoder/path helper preserves earlier ZIP regressions. These new JVM tests are CI-required, NOT executed locally (no Kotlin/Gradle).
- **Limits:** XHTML chapters must be well-formed XML without DTD declarations; unsupported/malformed books fail visibly, rather than requesting external entities. Sparse tar is explicitly unsupported. XLS/7z/rar remain separate unfinished native backends; do not silently add heavyweight dependencies or claim these formats accepted. Owner-controlled limits do not change external access-control or untrusted-data authority rules.


#### AF-MEM-112 — abandoned prerequisite is not an executed integration-test defect

- **Confirmed evidence:**6711e060dd6372e9a963924669f11fa001f57510, integration job111962483321: contracts=success, Godot=abandoned; aggregator correctly exits1. Upstream111957060092 and Windows package111958918532 show empty runner and steps; cancelled-job logs return404 BlobNotFound. Source compilation/JUnit Android gate passes.
- **Root cause:** reason for abandonment/cancellation unknown. Do not invent a code/compiler defect, weaken integration-gate success requirements, or call an outage proven from missing logs.
- **Recovery/prevention:** distinguish SUCCESS/CANCELLED/SKIPPED/FAILURE and inspect needs outputs plus runner/steps before changing source. One rerun-failed-jobs request per affected workflow on the identical candidate SHA preserves successful evidence and reruns downstream gates. Do not rerun only the final aggregator while leaving its abandoned prerequisite unchanged. Pending retry is not PASS; actual repeat results required. Avoid docs-only new candidate SHA during recovery; include local journal/memory evidence in the next source batch and put public recovery details in PR immediately.


#### AF-MEM-111/112 acceptance reconciliation

- Same6711e060dd6372e9a963924669f11fa001f57510 now has35/35 SUCCESS after the single recovery request per affected workflow; the six real EPUB/tar JVM cases compiled and ran in Android Plugin testDebugUnitTest. No source fix/gate weakening was required for pre-run cancellation. The cancellation cause remains unknown, not a proven outage.
- Subsequent evidence/policy-onlybc527487011f80cbc84fc882d007e330baba538b also has35/35 SUCCESS. Owner CI cadence now defaults to coherent implementation, gather/repair all known reds, one final full exact-SHA relevant suite; intermediate targeted GitHub retries require a materially useful faster diagnostic, not habit. Same-SHA recovery of unexecuted cancelled jobs does not demonstrate a product source repair. Physical-device/release acceptance remains distinct.
- Inventory prevention: classify immutable native owner-limit propagation only at reviewed exact paths; keep format sorting/representation sentinels distinct and fixture paths separate from runtime paths. Regression retains arbitrary LIMIT17/timeout99 as unclassified and private_network_denied as hard_boundary; full Kotlin comment rule cannot hide executable text after a comment.


#### AF-MEM-109 confirmed mechanism — long-context HTTP deadline cancels ongoing prefill

- **Exact evidence:**8efc513ce7f68e753eb63173758ad9f886bbdcd1, Core run37431321173/job112162690911, artifact11397491213 ZIP SHA256cc2afc72bb1a37f871182a13a5e654e61f49e7a2b00a2790ae94f670b640307c.20/21 scenariosPASS; long_context12841chars,90040.087ms, transport13/http0, request-scoped retryable failure, not model_failure. Engine task1105 has2688tokens,progress0.94,t88.68s, then cancel; later requests complete normally.
- **Confirmed cause/mechanism:** nonstreaming desktop HTTPRequest90s deadline expires during ongoing prompt evaluation. Core wrapper passes temperature only and benchmark outer scenario accepts up to120s. Earlier unknown failures are consistent with this mechanism, but lack historical engine/error evidence and are not retrospectively claimed proven identical. Runner CPU/prefill variability remains unexplained.
- **Do not repeat:** no blind rerun, timeout/scenario relaxation or false model-failure classification; do not stop/relaunch a healthy model due to request deadline. Successful repeat cannot establish repair. Preserve exact engine progress, request diagnostics and existing hard120s scenario gate.
- **Pending policy/fix:** owner-adjustable total deadline with per-request propagation, or progress-aware stall/total/cancel budgeting; owner selects materially different waiting behavior before source implementation. Keep normal defaults explicit, master stop active and benchmark quality/performance thresholds unchanged. CONFIRMED/UNRESOLVED, no product repair claimed.


#### AF-MEM-113 — verified work, not connection activity, controls Core waiting

- Owner delegated the waiting-policy choice; ADR0003 selects actual processed prompt token increases and generation deltas. Initial zero, duplicate counts, time/total changes, SSE pings and socket traffic do not reset stall. Capture immutable owner budgets once; persist via ConfigFile in private user storage, not a custom ProjectSettings file that is never auto-loaded. Zero disables operational budgets; representability is separate.
- SSE must retain raw bytes until complete frames: UTF8 codepoints can cross TCP/HTTP chunks. Require valid completion finish plus DONE; EOF, HTTP/backend/protocol and response-budget errors never turn partial text into successful content. Cancel sockets without killing healthy engine; propagate terminal request errors through model/legacy wrapper so a fallback cannot undo cancel/budgets. Windows Settings exposes save/error and explicit cancellation.
- Match protocol source to observed deployed engine, not an assumed installer revision: artifact engine11429/d81235049 verified against official server-context/server-task/README; earlier7fe450e19 inspection alone does not establish deployed version. No raw private prompts logged.
- Evidence tier:31 Python recovery/specialist/benchmark cases, producer chunked HTTP self-check and compilation/diff PASS locally. New actual Godot parser/config persistence/HTTP/terminal-wrapper tests pending CI (no local Godot); subprocess15s/30s guards prevent assertion hangs and wasted long CI waits. Existing120s actual benchmark and quality/performance gates unchanged. Source completion is not product acceptance. One coherent publication/full suite, owner monitoring links, no CI polling or blind retries.


#### AF-MEM-114 — inventory distinguishes runtime controls from acceptance probes

- Scope provenance matters: reviewed benchmarks/core scenario/evaluator/probe/watchdog/diagnostic findings are test_evidence, not ordinary product workload ceilings. Keep acceptance limits unchanged; never broaden benchmark classification into scripts/runtime merely because a filename contains benchmark. Preserve full-comment documentation classification precedence.
- UI SpinBox max_value4096 is display range only because allow_greater=true immediately follows; verify that paired property before classifying it as structure. Generic slider maxima and unrelated field maxima remain unknown. SSE frame slices are protocol byte offsets, not extraction budgets.
- Owner-snapshot use sites do not justify blanket classification of a reader. Separate reviewed configured defaults/env mappings and per-job timeout/output forwarding from fixed minimum dictionaries, standalone HTTP retry/deadline limits, generation token clamps and geometry. Regression keeps these unresolved rather than silently blessing them as adjustable. Inventory completion is a measured count, not inferred from earlier source heads; new runtime code can add findings.
- Validation:9 audit regressions exercise exact positive/negative distinctions and real inventory; source remains unchanged. This inventory review does not establish that all remaining operational constraints have UI controls.


#### AF-MEM-115 — adjustable text/vector budgets require consumption and cache identity

- Confirmed source restrictions: Agent feedback/trace/history/attachment/tool-result substr/slice literals, Memory retention/dedupe/index batch/text and vectorizer token/features were hardcoded; Desktop generation64..8192clamp ignored owner request above8192. Fix uses private ConfigFile OwnerResourcePolicy, visible folded Settings fields and actual consumers; defaults unchanged,0unbounded except positive indexing batch needed for progress. Android does not display Windows-only generation controls.
- Representation is separate from operational policy: bundled llama.cppd81235049 uses signed32 n_predict_max and-1 for limitless generation. Validate int/finiteness/integrality/range before transport, map owner0to-1, reject overflow rather than wrap; actual model context/EOS/owner wait/byte budgets still apply. Static assertions requiring literal64..8192, history4/800 are updated to require owner-policy propagation; quality/recovery/safety gates remain required.
- Index setting changes cannot merely change newly queued text while retaining old vectors. Persist versioned index-text/token/feature policy signature; invalidate derived vectors and queued work on change/restart mismatch, rebuild from retained canonical records, leave lexical retrieval available. Do not delete canonical data during vector cache invalidation. Exact dedupe index also rebuilds when owner policy revision changes. Feature/token loops enforce selected bounds including bigram lookahead;0disables these operational budgets.
- Save partial updates without resetting unrelated fields; failed saves do not update active cache/revision. Zero retention means no trimming, not retaining zero records. Lowering positive retention can remove old data on future add (existing scoring algorithm); tell owner clearly, do not claim future capacity controls restore historical discarded content. Context/text caps being adjustable does not create larger physical/model capacity.
- Validation tiers:47 available Python contracts/evaluator/audit PASS; real Godot persistence/invalid numeric/UTF8/consumer/retention/dedupe/vector invalidation/batch regression prepared, NOT locally executed (Godot unavailable). Bounded30s smoke avoids assertion hangs; current remote candidate remains untouched while Windows package completes. Source preparation and classification counts never equal release acceptance.


#### AF-MEM-116 — full identities, honest verification and owner ingestion controls

- Confirmed on source parent3bb31194e13101fe0cac99a539dfc300c327696d: CodeSpecialist public Python definition comparison scanned only first120000 chars, Work action_id was truncated at256, and CognitionLayer returned ok=true when verification transport failed or JSON parsing failed. Consequences: late definitions invisible to preservation checks, colliding action identities and falsely successful verification. Full-source structural comparison does not execute imported code or replace behavioral testing. Identity fields must remain complete; clip display/context instead.
- Prepared fix: full-source regex scan; complete Work action_id; verification unavailable/malformed/missing fields/non-numeric or out-of-range confidence becomes ok=false/confidence0 with preserved unverified answer and issue. Owner-adjustable budgets cannot disable redaction, verification contract validation, imported skill confidence ceiling or unsafe-action/master-stop guards.
- Retention0 means unlimited, not empty; preserve defaults and partial ConfigFile saves. Per-instance explicit agent step budgets retain precedence. Unlimited loops must still check execution guards every model/tool step. JSON depth/scalar/record settings are snapshotted once at parse start; mid-parse owner changes apply next time. No promise of infinite physical stack/RAM/model capacity.
- Reviewed CI/benchmark timeouts and workloads are test evidence through exact statement/path rules, never broad installed-product exemptions. Mutation3–10, normalized scores and hash widths are format/quality contracts, distinct from operational retention/attempt/context budgets. Unknown new statements remain unclassified.
- Existing built-in Godot ZIPReader expands a member before checking expanded byte counts; exposing budgets alone does not establish pre-expansion memory safety. Native bounded readers have independent acceptance; do not describe this compatibility path as a pre-allocation zip-bomb defense. Prepared follow-up uses central-directory entry and expanded member sizes before ZIPReader open/read, validates actual result size and reports unsupported ZIP64/multi-disk/encryption through requires_extractor. This preflight still requires runtime acceptance; source alone is not proof of pre-allocation safety.
- Prevention: extended genuine owner-resource fixture covers late definitions, bounded/unbounded guarded tool loops, UTF8 redacted Work text, learning retention consistency/priorities, imported skills, JSON budgets/snapshot and RTF truncation, plus unavailable/malformed verification. Local Python contracts56PASS; Godot scenarios NOT LOCALLY EXECUTED (AF-MEM-107). Runtime/package/device acceptance remains required; no release readiness increase from source preparation.


#### AF-MEM-117 — adjustable Evolution retries need live authority; native acceptance must mean extraction

- Parent3bb3119: Evolution adapter lock identity alone did not query current master/permission/update state between attempts; AutonomySettingsManager had false DEFAULT_SETTINGS but missing-field _apply fallbacks usedtrue. Existing foundation source contract still incorrectly required defaultmastertrue. Prepared fix keeps defaultsfalse, missing fieldsfalse and product controller supplies a live authorization callback checked with every lock-token test before/after awaited proposal/verification. Standalone adapter fixtures retain explicit test foundations; product callback is bound at bind_foundation. No manual permission or independent verification is waived by an unlimited retry setting.
- Pending-winner TTL is owner lifetime policy (86400seconds default,0no expiry), not activation authority: malformed timestamps rejected; single-use, current stable SHA, winner hash and fresh clean verification remain required. Tournament population stays3–10. Retention0 keeps all records/phases/pending winners; caller recent(0) returns all retained records.
- Confirmed AndroidFileRuntime placeholder successes existed for XLS/7z/rar/GIF, unknown binary and failed local STT. Prepared correction returns unsupported_format/ok=false for missing native backends or binary content, and failed/empty STT is an error; successful transcripts obey per-job output limits. GIF now routes to actual local image OCR and reports first_frame/truncated explicitly, never full-animation acceptance. Actual XLS/7z/rar native implementation remains incomplete; no heavyweight dependency or format support falsely claimed.
- Validation:104 available Python source/contract regressions passed before native wrapper follow-up; genuine Godot tests extended for guarded adapter locks and owner record/pending/TTL semantics plus fail-closed autonomy preferences. New Kotlin/Godot behavior still NOT locally executed (toolchain unavailable). Exact-SHA CI/device gates remain required; passing source assertions cannot establish extractor/voice/device success.


#### AF-MEM-118 — source settings save calls are not durable owner persistence evidence

- Confirmed source parent3bb3119: FileIntelligenceClient/PublicWebManager persisted limits through ProjectSettings.save; Settings ignored its result and always reported saved. Packaged resource locations are not a reliable private writable user configuration path. No packaged failure is retroactively claimed reproduced locally: Godot unavailable. Source contains no failure propagation or private reload contract.
- Prepared fix uses OwnerLimitPersistence grouped ConfigFile at user://owner_operation_limits.cfg. Preserve other groups/unknown config fields; write temporary then rename; check save error before modifying active values, exporting backend env or restarting. Reject nonnumeric/nonfinite/fractional integer/negative/out-of-representation settings rather than silently clamp bad owner input. Existing valid legacy ProjectSettings are initial fallback; private persisted limits win on reload. UI reports failure and load diagnostics, not saved/success. Web timeout0 disables HTTP deadline; positive count/size budgets remain productive and raisable without artificial maxima.
- Remove arbitrary minimum2k text/64k response/256 URL, minimum1024 file/PDF/expanded bytes and10000render pixels; minimum1 represents a positive productive budget, not hidden total-work ceiling. The UI mirrors these minima. Public/private network, redirect revalidation, login/CAPTCHA/paywall boundaries remain required.
- Prevention: genuine Godot fixture saves/loads separate clients, preserves web/files groups, verifies above-old-cap values and single-byte budgets, rejects invalid numeric settings and verifies failed-path save leaves current policy unchanged. Python source contract checks private paths and save-before-apply order. Actual Windows/Android persistence/atomic-rename acceptance remains pending CI; no release readiness increase.

### AF-MEM-119 — File suboperation ceilings, rounded PDF allocations and missing master authority

Symptom/source evidence: File service truncation appended a marker outside the requested text ceiling; PDF preflight used continuous area and an arbitrary0.01 scale floor despite PDFium allocating rounded-up integer dimensions. File tools used direct HTTP and fixed5000/100 clamps, bypassing the platform-aware owner client. Windows request/cache/EPUB/archive/optional vision/STT/video suboperation budgets were still source literals or deployment-only values. Computer master resolver returnedtrue for missing settings and searched at mosteight ancestors; security callback malformed values defaulted toallowed.
Environment: source based on3bb31194e13101fe0cac99a539dfc300c327696d; mechanism confirmed by source review, packaged reproduction NOT EXECUTED locally. Official pypdfium2 helper source documents ceil(width*scale) and ceil(height*scale).
Fix/prevention: truncation marker stays inside output ceiling; finite positive PDF dimensions and integer pixel product checked before native allocation, decreasing scale without a policy floor. Six actual-body local unit tests include skewed/large geometry and tiny output budgets; real PDFium1×1 allocation regression is queued for integration CI. Fourteen Windows File suboperation fields use private checked settings/UI/environment, and extraction cache identity includes PDF/EPUB/video policies so raising a budget cannot reuse an old partial result. Agent File tools reuse AttachmentManager.intelligence; never spawn a disposable client that owns another backend. Require explicit boolean master authorization and walk actual tree ancestry; malformed supplied security guards deny. Success fixtures explicitly supply authorization; dedicated missing/malformed/deep-ancestry/master-stop cases preserve real guard and unsafe retry behavior.
Avoid: treating a response retryable flag as a retry budget, classifying automatic redirect suppression as an adjustable redirect count, or declaring missing native XLS/7z/RAR extractors implemented. Automated redirects staydisabled so every manual hop receives SSRF validation.
Status: source fixes/prevention prepared; actual Godot/Android/PDFium CI acceptance still required. No native dependency chosen or new release authorization inferred.


### AF-MEM-120 — recovered Work snapshot and end-to-end owner budgets
- Environment/evidence: replacement V1.5 Work, PR103 starting3bb31194; recovered original unpublished checkout at same HEAD. Original source has49 changed tracked paths and2 authored helpers. New isolated checkout preserves the original unchanged.
- Symptom/root cause: chat described unpublished controls, while fresh GitHub still had only26 published controls. Recover actual authored files; never recreate from conversational counts. Copy preserving old mtime appeared stale in the managed workspace; write bytes and compare SHA-256 for every adopted file. Exclude generated Godot UID/import/runtime artifacts from publication.
- Confirmed production defect: Project Index and both trusted-copy bridges silently clamped selected owner limits; zero became one. Partial index traversal also deleted existing unvisited records. Fix: nonnegative end-to-end budgets, zero-unlimited, actual extra eligible-file detection for partial coverage, no stale deletion on limited traversal. Trusted-root/sandbox/ignored-directory authority unchanged. Regression: real SQLite index, exact-fit and overflow, zero, negative and >100000 schema input; real Godot copy algorithms on both bridge classes.
- Verification failure hygiene: use JSON.parse error code for unavailable/malformed answer verification, preserving ok=false/confidence0 without parser logging untrusted malformed response content. Unknown File/Web setting names fail before persistence/environment side effects.
- Local runtime workaround: official Godot4.7.1 Linux is available and ran actual production GDScript smokes. Python pinned File Intelligence requirements enable real parser tests. Optional local OCR runtime remains absent on this host: its integration test is SKIPPED, never PASS. Fixture ObjectDB/resource exit diagnostics remain separately visible from runtime assertions.
- Status: source regressions verified locally; same-SHA CI/package/device acceptance remains journal-owned. This entry does not declare source freeze or native XLS/7z/rar implementation.


### AF-MEM-121 — coherent CI exposed stale test schemas, preserve production safety
- Exact source: fc20ec4f3457a65b51fdb9c874ed37ee23445767, PR103. File Intelligence run37531842599 AST cache-key fixtures lacked production PDF/video policy constants; offline autonomy fake parsed TOOL_RESULT before the untrusted-data delimiter/partial-coverage field introduced by real runtime. Cross-subsystem run37531842485 and Work37531842564 failed through the same offline fixture; downstream integration gate correctly failed.
- Fix/prevention: supply actual service default constants to AST fixtures; require the actual UNTRUSTED_TOOL_RESULT_DATA envelope and decode its JSON payload. Never remove cache identity fields or weaken tool trust framing to satisfy a stale fake. Both root causes locally reproduced and repaired; full new-SHA CI is still required.
- Godot fixture loading: VoiceLogger class references autoload AuroraVoice. Loading as a static fixture dependency before autoload initialization failed compilation; runtime load inside deferred _run resolves the actual production script after initialization. Computer overlay has no class_name: fixture inheritance must use its explicit script path. No production autoload workaround is necessary.
- Local owner/UI evidence includes actual rename, folder overflow/cancellation, private voice redaction/rotation, Android tool budget routing and text-only Computer completion remaining UNVERIFIED. Routing fixtures do not claim native parser/device execution.

### AF-MEM-122 — local Android plugin AAR does not bundle Maven archive dependencies
- Confirmed source fc20ec4f: plugin uses Commons Compress/TarArchiveInputStream and ZstdInputStream; export plugin listed only PDFBox/Tesseract dependencies. Zstd compile dependency selected the JVM JAR, whose native binaries are not the Android runtime.
- Fix: export existing pinned commons-compress1.27.1 and zstd-jni1.5.7-3@aar alongside existing dependencies; Android compilation selects @aar, host JVM tests retain regular JAR as upstream recommends. No version upgrade or new backend selected.
- Upstream actual Android AAR inspected: SHA25685c13f90649746aaa622ee2bd67ec142bfbb61cae296c584a98c787834eb26cf; contains classes.jar and Android JNI for arm64-v8a,armeabi-v7a,x86,x86_64. Production presets select arm64-v8a/x86_64.
- Prevention: shared Android build helper checks produced APK for both JNI libraries and actual DEX class definitions for ZstdInputStream/TarArchiveInputStream before accepting/signature checks. Finding descriptor references alone is insufficient; regression rejects reference-only DEX and missing ABI. Synthetic parser fixtures establish gate behavior, not an actual newly built APK PASS. Required exact-SHA package CI remains pending.
- Primary guidance: https://github.com/luben/zstd-jni/blob/master/README.md and https://docs.godotengine.org/en/stable/tutorials/platform/android/android_plugin.html.


### AF-MEM-123 — unpublished native parser acceptance and execution transport handoff
- Native work started at bf96ae7202fd89e6441c63b1bd53d1afca737773; actual isolated checkout /workspace/scratch/29cc88377b5e/v15-recovery.38 JVM parser/resource assertions PASS locally on Java17.0.20/Kotlin2.2.21, plus actual Godot and96PythonPASS+1SKIP+2subtests. The new native source is UNPUBLISHED; bf96 CI does not test it. Never convert local results into new-SHA Android/package/device PASS.
- 7z uses existing Commons Compress1.27.1 with declared optional XZ1.10. Pinned setMaxMemoryLimitKb passes KiB unchanged: inspect exact pinned source rather than copying newer1.28 API/behavior. Set header/LZMA budget before opening, preflight entry/expanded sizes, read sequentially for solid archives; never extract paths.
- junrar8.0.0 now supports RAR5; old no-RAR5 assumptions are stale. Its default4GiB dictionary is overridden from owner expanded-byte budget before decode. Raw RAR header preflight precedes metadata allocation; input/member/count/header bounds, encryption/multivolume denial, single-volume channel/progress/output cancellation, no adjacent-file lookup or disk extraction. Real hostile-link fixture contains five links plus two legitimate regular payloads: do not wrongly assert every entry is a link. Pinned fixtures include upstream URLs/SHA256 manifest.
- POI core5.5.1 only: raw OLE file/directory/depth/stream-size/cycle/shared-link preflight before POIFS objects; peek and validate SST counts using marked buffered RecordInputStream before shared-string allocation, reset then parse actual continuations. Positive private owner file/directory/depth/shared-string/sheet settings are passed in an immutable per-job client snapshot; existing row/cell/output budgets propagate. Parse BIFF8 raw cached values, label formatting limitations, never run formula evaluator/macros. Tested real cached numeric/string formulas,50001cells and129 nested directories accepted under raised owner depth.
- Listing0 intentionally hides native ZIP/tar/7z/RAR listing; do not turn full content into false partial. Actual positive overflow remains visible. Native bitmap preflight uses rounded Float dimensions/Int representation and monotonic Float bit search, removing arbitrary0.01 scale floor and1% overshoot before allocation.
- Compile/export/package dependencies and actual DEX definitions/JNI must agree; preserve notices/licensing. New POI/junrar base classes inspected major52(Java8). POI transitive Commons IO2.21.0 replaces2.16.1; local classpath must match actual Gradle resolution. Host Java lacks javap/full JDK tooling, but matching standalone Kotlin compiler works. No-provider SLF4J/Log4j diagnostics and tar deprecation are not failed assertions or proof of Android compatibility.
- New confirmed external blocker: execution transport disconnected while preparing publication ("CreateProcess ... exec-server transport disconnected ... recovery timed out after25s"). Subsequent read-only calls stalled. Publication manifest was not transferred and source cannot be safely uploaded from memory. GitHub connector can preserve factual journal/memory; do not fabricate a source commit or promise hidden/background progress. Recover the actual checkout and hashes first. Full source ownership/readiness/status stays in master log; this entry is prevention/reference, not a competing journal.


### AF-MEM-124 — execution restored does not restore an unpublished Work filesystem
- Evidence baseline: c9cc3b328be8e26b9507d310a3a4f40658705b41. exec works again, but /workspace/scratch/29cc88377b5e contained only runtime placeholders; prior v15-recovery, native source, compiler and test logs were absent. Search /workspace found no XlsTextReader.kt or native publication manifest/logs. The original679acfb checkout exists at b12d13fa with no tracked modifications. Why the files vanished is UNCONFIRMED; execution restoration alone is not evidence of recovery.
- Preserve historical AF-MEM-123 test claims as historical, not as results for reconstructed code. Clone GitHub truth and re-run real checks; never fabricate the absent native package from conversational summaries or report it published. Native XLS/7z/RAR readers remain missing from current source.
- Newly executed source repairs: PDF bitmap budget applies native Float geometry and ceil integer dimensions, using overflow-safe division and a monotonic positive Float bit search before allocation; no0.01 scale floor or1% overshoot. Disabled ZIP/tar listing does not mean content truncation; genuine positive listing/entry/content overflow still reports partial.
- Fresh local evidence: real Kotlin2.2.21/JVM17 compile and19JUnit tests PASS;21Python owner/package contracts PASS. Actual Android renderer/device acceptance is still pending. Tar deprecated getter warning retained, not a failing assertion. Missing pytest was restored with python -m pip install pytest; do not confuse dependency absence with production failure.
- Prevention: publish coherent source plus factual journal promptly; no local-only acceptance can establish durable source completion. Release/claim status remains solely in master log.


### AF-MEM-125 — fresh native reconstruction and installed-format prevention
- Evidence baseline57d66899ff473d3e7dc9d1ee9ba009c1a43cfb6a. Missing prior native snapshot does not prevent independently implementing authorized remaining V1.5 scope. Fresh implementations and real tests replace reliance on absent AF-MEM-123 source/results; no claim of byte-for-byte recovery.
- SevenZFile1.27.1 allocates raw nextHeaderSize before its metadata memory estimate and allocates decoded header bytes from declared unpack size. Preflight signature/offsets/raw size and encoded COPY/LZMA/LZMA2 header coder/unpack-size topology before builder; set library memory limit in KiB for metadata/dictionaries. Real COPY-encoded-header regression validates accepted topology; synthetic oversized expansion fails before library allocation. Sequential reads avoid solid random-access quadratic decode; guarded channel checks cancellation during library skips; unsafe paths/links/anti-items never become disk destinations. Unsupported codecs/topologies fail explicitly.
- junrar8.0.0 is pure-Java RAR4/RAR5; dictionary owner budget reaches both RAR5 window and RAR4 PPM checks in pinned source. Raw header preflight bounds header count/bytes and packed skips, rejects encrypted/multivolume headers and split members. Use a single-volume manager and guarded channel; bounded output checks before writes. Do not call default adjacent-volume discovery. Hostile links fixture legitimately contains two regular payloads, not zero. Fixtures include pinned source URLs and SHA256 manifest plus upstream notices.
- POIcore5.5.1 only, no OOXML/full HSSFWorkbook/evaluator runtime: raw FAT/directory/cycle/shared-link/depth/stream-size preflight before POIFS; peek SST count through marked buffered input before SSTRecord allocation, preserving continuation parsing. Read BIFF8 raw values/cached formula results; clearly warn about unapplied styles/dates and no formula/macro execution. Older/encrypted variants fail explicitly. Library POIFS retains its own1000-depth structural safeguard; owner depth does not promise unlimited native stack capability. Native positive owner controls persist privately, enforce Int representation where required and are copied once per job.
- Actual new local evidence:39 JVM format/budget tests PASS,37Python owner/package/Android-E2E contracts PASS; fresh official Godot4.7.1 parse and owner persistence/snapshot smoke PASS. Tests include actual50001cells and129nested directories, Unicode SST continuation, cached numeric/string formulas, RAR4/RAR5 solid/hostile/encrypted payloads,7z decoder/input/header budgets and cancellation. Existing20ObjectDB/8resource fixture cleanup diagnostics, SLF4J/Log4j no-provider logs and deprecated tar getter remain visible; none proves Android/device acceptance.
- Compiler classpath must match selected dependency versions: POI resolves CommonsIO2.21.0 over old2.16.1; wait until dependency transfer finishes before compiling. Iterable Java contentMethods needs explicit nullable fallback, not List.orEmpty extension. Text member limits do not govern aggregate metadata; metadata is bounded by expanded-byte budget separately.
- Old retained Godot artifact was actually truncated: ELF20MiB missing section headers at144583440 and stored8MiB zip lacked central directory. Segfault was not a GDScript regression. Re-download official4.7.1 zip76056717bytes/SHA256c7ff14fd28472c8d4f193043de30278dcf7e5241a1dcf7566b02e27addaa33ba, verify zip CRC then execute fresh binary. Use workspace-local venv when turn-restored user pytest installation is missing.
- Prevention: required DEX definitions include SevenZ/XZ/junrar/POIFS/SST plus existingZstd/Tar and both JNI ABIs; matching Maven dependencies exported, license assets/notices preserved. Extend existing offline installed-APK E2E with hashed tiny XLS/LZMA2/RAR5 fixtures through actual FileIntelligenceClient/plugin. Host/JVM/DEX tests never substitute for these new actual Android execution cases; pending CI is not PASS. Avoid immediate docs-only HEAD updates during expensive cancel-in-progress workflows; record produced SHA in the next coherent journal block.


### AF-MEM-126 — Project Index coverage, per-file policy and Core APK compression
- Baseline5683bfe0f58c80fdc013114649f514257ec9e48d. A traversal byte filter must not mark skipped sources deleted. Retain unseen rows whenever file/byte/read/traversal coverage is incomplete; purge explicitly unsafe symlink paths separately. Probe actual read size with max+1 because stat can race source growth. Persist policy and symbol truncation per file, not globally: partial scans otherwise falsely accept unvisited files after owner changes. Additive derived SQLite migration preserves existing rows and rechecks columns under the writer lock.
- Defaults remain4MiB/500symbols/100search/200symbol results; eight private owner fields propagate service/client/tool limits, zero means unlimited. Actual extra matches prove response overflow; no fixed1000candidate cap. SQLite LIKE case folding is ASCII-only: Unicode symbol name matching needs Python casefold over streamed candidates. Search queries no longer silently drop terms after20; ellipsis markers count inside the excerpt budget. Stored symbol clipping remains visible even when a requested symbol was omitted.
- Exact568 Android contract job112551383944 failed because the simulated completed report omitted newly mandatory native formats. Align the complete fixture; individually missing XLS/7z/RAR remains a rejection. Do not weaken installed-APK acceptance. Actual Android plugin job112551383252 testDebugUnitTest/installGodotPlugin BUILD SUCCESSFUL in9m34s validates this SHA on real Gradle, while Android APK job112551383360 failed at compressStandardReleaseAssets with Java heap space.
- Official Godot4.7.1 Android application template has4536m heap and no gguf compression exception; bundled Core is1282439264bytes. Configure installed application template before export using a narrowly scoped gguf noCompress policy (AGP AndroidResources API), preserving other assets and all model/hash/signing/runtime invariants. Verify the actual APK model ZIP_STORED metadata after export; local template/ZIP tests do not establish full Gradle/APK/device success. APK size can increase by storing dense weights.
- GitHub tree publication must preserve file modes; previous blanket100644 reset executable runner. Restore100755 in the coherent repair and derive future tracked modes from the index/filesystem rather than a constant.


### AF-MEM-127 — sandbox owner coverage, staged rollback and export installation timing
- Baseline0a7cd1bd10d352f864d0e99cdf297510d38df105. Sandbox read/tree/list/events fixed caps silently lost coverage; byte checks after read allocated the entire source. Five private owner settings preserve defaults, allow raised/zero and propagate client/tool/service request budgets. Windows service checks stat before opening and reads only budget+1; actual2001files and5000001bytes distinguish exact fit/overflow/zero. Auth401 for missing token and400 for path escape are existing contracts, not new failures to change.
- Godot local tree/copy/read/write/index IO must reject links, removal must unlink a directory link without recursing outside. Staging a rollback before replacing current work prevents a linked/unreadable snapshot from destroying existing files. Rename current work to backup, rename staged work into place, restore backup if apply fails; report recovery backup and restore code on failed restoration. Real Godot fixture verifies normal rollback, denied hostile snapshot retaining current work and untouched external file after cleanup. Windows service authorization/isolation/process retry boundaries remain unchanged.
- Exact0a7 APK job112555558672 rejected uncoupled --install-android-build-template before heavy build. Pinned official Godot4.7.1 main.cpp only passes installation flag to EditorNode when an export preset exists: adding standalone --quit would exit without installing. EditorNode installs template before platform.export_project. Restore coupled install/export; existing AndroidExportPlugin._export_begin applies the shared narrow GGUF Gradle policy after template installation and before final app build. Original Android contract passes unchanged; no fake standalone installation success.
- Real EditorExportPlugin can only instantiate in editor mode; plain headless script probe fails by design. Actual --editor probe validates idempotent policy writes and restores files. Standalone SceneTree editor fixture produces209ObjectDB/Canvas/RID exit diagnostics even though assertions pass; these are retained explicitly and are not full APK acceptance. RefCounted exporter must be dropped with null, never freed with Object.free.
- New local evidence:124PythonPASS+3subtests with real service/SQLite/ZIP and existing Computer safety regressions; actual Godot owner smoke and export-hook assertion markers PASS; canonical Android contract V1.4.1.1/code100007 unchanged. Exact reviewed operational lines are classified by full escaped line patterns; leave untouched fixed execution/transport/metadata limits unresolved for further scope review, not a blanket audit-zero shortcut.


### AF-MEM-128 — Android feature-tag case and execution-only outage
- fb565eba2b903ffbb7e840fcc832a0f7771f92ed APK112558683161 and normal-path112558907343 exported successfully but actual ZIP_STORED verifier rejected compressed Core. Godot4.7.1 get_platform_features emits lowercase mobile/android: https://github.com/godotengine/godot/blob/4.7.1-stable/platform/android/export/export_plugin.cpp . Uppercase Android guard silently skipped GGUF policy; the synthetic fixture repeated that error. Correct published guard/test to actual tag and negative windows fixture; actual APK gate remains required. An editor hook's unit success is not actual export acceptance.
- New unpublished output-control source passed147Python+3subtests and actual Godot owner/Research privacy/resilience/loopback-byte checks. HTTPRequest unlimited body uses-1, not0: https://docs.godotengine.org/en/stable/classes/class_httprequest.html . Actual2097153byte response fails2MiB and succeeds exact/zero. Track total errors independently of retained diagnostics, and keep title/summary clipping visible.
- Speech chunk append punctuation must share output budget; apply configured limit inside fenced code too. Tiny1/2/3-byte-character budgets must make progress and preserve source characters. Use AudioStreamPlayer.volume_linear for true0mute rather than max(gain,0.001). Owner settings never relax external-query240/24/private-file/curation boundaries.
- Real Godot probe confirmed marked credentials after password and token= values escaped query/telemetry; local fix redacts assignment/JSON/whitespace/Bearer forms before token filtering or error clipping, with fail-closed regex fallback. Probe changed both retention flags from true to false. This is evidence for unpublished local source only.
- Command service subsequently stopped returning even login=false pwd in /tmp, while GitHub remained reachable. No filesystem-loss evidence exists yet; do not call it missing or fabricate a source recovery. Recover the actual /workspace/scratch/29cc88377b5e/v15-recovery and logs before publishing that local package. A known small observed CI fix can be implemented independently from exact published/cached GitHub source, labelled new local tests NOT_EXECUTED and accepted only by its own CI.
- Sole claim/source/CI status remains in PROJECT_MASTER_LOG; no second journal or speculative percentage increase.


### AF-MEM-129 — exact execution outage result and produced source checkpoint
- Independently returned error for both pending source command and login=false pwd in/tmp: CreateProcess failed to query exec-server capabilities; environment registry409Conflict/environment_offline: Environment is not connected. This confirms execution unavailability; it does not prove filesystem loss, rejected approval or product-test failure. Repeating permission requests cannot fix it.
- Actual CAS publication2c7338dc4d1f1ffb0002c0dadf0dc2fd32d5e8bd/treeb8978b8a749da9845afb4920964dfec23c476203 contains three independently implemented Android-tag source/test repairs plus factual journal/memory. That remote repair's local tests are NOT_EXECUTED;147Python/Godot results belong to unpublished Research/Voice source, never to2c.
- Final emergency docs checkpoint records actual source SHA/error; normal coherent source-batch policy remains. Restore actual checkout and reconcile fresh GitHub before publishing reserved local source. Do not infer a code freeze or version acceptance from this handoff.

### AF-MEM-130 — execution recovery preserves actual unpublished source
- On2026-10-07 the same scratch checkout became executable again and its11modified Research/Voice paths plus2new HTTP fixture files survived. Preserve local appended claim, import exact published Android-tag fixes and remote emergency memory/journal entries, then reset only the git index/base (--mixed) to fresh5886. Do not use destructive clean/reset or rebuild an allegedly lost package.
- Fresh5886 exact checks43SUCCESS/3SKIPPED validate prior native/index/sandbox/Android-tag source; re-executed real owner/Research/HTTP fixtures validate local source independently. Keep missing Python test dependencies visible rather than treating collection errors as product regressions or PASS. Existing editor/owner shutdown diagnostics remain explicit.
- Marked credential redaction, HTTP unlimited-1, speech code/tiny chunk progress and true linear0mute prevention tests are retained; seeAF-MEM-128 for implementation lessons.

### AF-MEM-131 — unlimited timeout versus exhausted collection and backoff arithmetic
- Engine HTTPRequest timeout0 means unlimited. A collector must represent exhausted global budget separately (-1preflight here), preserve positive subsecond remainder and still impose finite global budget when request deadline is disabled. Actual loopback delayed reply proved timeout1failure,timeout0success,global300msfailure and expiredpreflight rejection.
- Exponential backoff with owner-unlimited failure counter cannot safely pow2 in floating point. Double with signed64 saturation, cap optional ownermaximum independently, stop once saturated. Testhugefailurecount/0base/0maximum/raisedcontrols. Persist full source identity:96char truncation could collide distinct sources after restart.
- Ownerdiagnostic0 may retain full text but credential redaction must occur before all clipping. Testlongdiagnostic/longIDs/lowcap credential exclusion. Productprivacy/query/curator boundaries remain unchanged; full provider pagination remains separately unfinished.

### AF-MEM-132 — snapshot request defaults and Windows reparse boundaries
- Operational write/snapshot limits must travel in immutable authenticated request;0 removes resource ceiling, never link/auth/masterstop safety. Validatebytes withUTF8, exactfit and real5001-entry trees; failed snapshot/rollback must preservecurrentworkspace.
- Pydanticdefault=moduleconstant captures value at modeldefinition; existing operator default/runtime test overrides would stop working. default_factory reads current fallback when fieldomitted; explicit ownerrequest still wins. Preserve compatibility and testoldfallback plus newraised/0cases.
- pathlib.Path.is_junction is absent in pinned CI Python3.11. Use non-following stat.st_file_attributes and stat.FILE_ATTRIBUTE_REPARSE_POINT to reject NTFSjunction/reparse entries; genuine Windows mklink/J fixture is required. Linux symlink success is not junction/device acceptance.
- Godot transport capture fixture proves production payload construction only, not nativeWindows action or end-to-endHTTP. Actual authenticated service filesystem gates separately verify requested policy, authorization and atomic rollback. Keep those evidence boundaries explicit.

### AF-MEM-133 — cancellation is not HTTP disconnect or Docker CLI termination
- Awaiting HTTPRequest completion after a one-time mastercheck leavesownedserverprocess running whenmasterchanges. Revalidatewhilewaiting, issueauthenticatedcancel by a trusteduniqueID andrequireactualterminationack; returnuncertain/neverauto-retry whenackisabsent. Pre-cancel/reusedIDmustneverlaunch; testsusegenuinechild/grandchild, heartbeat, actualGodotHTTP and service.
- Stopallmustsetterminalserviceflagunderlaunchlock beforeenumeratingownership. Otherwise a lateexecution request canstart afteremptyregistryack andbeforebackendkill. KeepfailedstopPID/container records forretry. NativeGUIworkerprocessesalsorequireownership; GUIeffects alreadyperformedcannotbefalselyreversed.
- Docker/Podman daemoncontainers survive killingtheclientprocess. Giveeachrun aninternallygeneratedcontainername, killownedCLI/groupandexplicitlyremove thatname; failedcleanupisuncertain, notsuccess. Testactualrunningcontainer andactualabsence. CI canpreparea fixtureimageandpinitslocalcontentaddress; product--pull=never remainsprotected. Officialrunnerimageprimaryreference: https://github.com/actions/runner-images/blob/main/images/ubuntu/Ubuntu2404-Readme.md . LocalDockerabsence is NOT_EXECUTED, never daemonacceptance.
- Nodeexit/restart must stop ownedjobs while sidecarregistry isreachable, notblindlyOS.kill backendfirst. A bounded authenticated loopback synchronousstopack isused because Nodeexitcannotawaitframes; failedackretainsbackendforretry/parentwatchdog and preventsduplicaterestart. GracefulRPCevidence doesnotproveabruptcrash/OSkill cleanup.
- ActualGodot/uvicornfixture provesmasterstop,transportfailurecancellation,unavailableackuncertaintyandactiveprocessstopbeforeexit. UnitfixturesforpuremultiprocessingGUI-shapedworkersarenotphysicalWindowsdesktopacceptance. KeepnativeWindows/DockerexactCIrequired.

### AF-MEM-134 — actual dependency shutdown API and process namespace proof
- Unpinned Computer CI installed FastAPI0.142.2 where app.add_event_handler is absent; pinned0.116.1 alone did not expose this import failure. Use public asynccontextmanager lifespan and verify genuine live-process shutdown in both dependency environments. Primary API: https://fastapi.tiangolo.com/advanced/events/ . Do not hide incompatibility by weakening CI or counting old-SHA greens as repair evidence.
- Huge owner deadlines must not be passed directly to platform blocking waits. Poll in short bounded intervals while preserving captured output and owned cancellation; zero removes operational deadline only. Engine body_size_limit uses -1 for unlimited, not owner-facing0.
- A container guest PID may differ from mounted /proc PID: confirmed os.getpid5 versus /proc/self/stat7088 with NSpid7088/5. Record each fixture process visible proc identity and start time before readiness; verify stopped heartbeat and absent/reused/zombie identity. Reading /proc/guestPID can inspect an unrelated ancestor process and yield false failure or false success. Keep real Windows tasklist and Docker daemon checks separate.

### AF-MEM-135 — truthful output clipping and container fixture engine identity
- _redact previously silently clipped at MAX_OUTPUT before caller could observe full sanitized length. For owned command output redact fully first, apply immutable owner budget afterward, report partial/truncated/limit_reached and sanitized length. Budget0 removes truncation, never credential redaction. This change alone does not bound communicate memory; keep producer buffering separately unfinished.
- CI prepared a Docker-only local image ID while product _container_engine prefers installed Podman first. At923128a Linux112638948050 the actual container fixture failed readiness after20seconds; logs did not expose early HTTP result, so final runtime cause remains unconfirmed. Explicitly select Docker in the Docker fixture, retain mandatory daemon gate and emit early response diagnostics. Never change product engine preference or count this unexecuted local repair as daemon acceptance.

### AF-MEM-136 — drain multiprocessing responses before joining owned GUI workers
- Confirmed on4fa501c source: genuine spawn worker queue.put1MiB returned timeout after3seconds because parent join preceded queue.get. Child Queue feeder needs parent to drain before process exit. Poll queue within existing operation deadline, then require worker completion; malformed/hung responses remain fail-closed. Actual large-response regression must run alongside owned shutdown and unsafe retry gates; pure worker transport is not native screenshot acceptance.
- Exact4fa501c Linux112639837575 actual Docker daemon cancellation passed, but real GUI-shaped worker shutdown returned termination_confirmed:false. Concurrent request/shutdown Process.join/status access is a source-supported race hypothesis, not yet proven exact cause. Serialize lifecycle wait/status/termination, retain failed ownership and explicit uncertainty, repeat genuine shutdown regression and require exact-SHA CI. Do not fake confirmation or retry unsafe actions. Close response queue only after worker is proven stopped.

### AF-MEM-137 — producer budgets precede returned output clipping
- communicate() stores complete stdout/stderr before applying returned-output character budget. Replace with concurrent binary pipe drainers sharing a captured-byte budget; default8MiB is a new explicit owner-adjustable resource ceiling,0 intentionally removes it. Keep at most budget bytes plus bounded read chunks, drain/discard excess while owned termination runs, report output_budget without an unsafe partial credential prefix. Genuine infinite producer, combined stdout/stderr exact byte fit, multibyte UTF8 and default8MiB+1 cases verify behavior; this is not a measured total process RSS bound.
- Register and start reader threads under ownership lock so cancellation cannot join an unstarted thread. Recheck overflow/read failure after EOF to close event/completion races; read failure cancels actual producer and never returns success. UTF8 replacement is explicitly reported. Failed live pipe ownership remains retained; streams close only after capture threads stop.
- A departed POSIX parent may leave descendants holding inherited pipes. Kill the owned process group even if parent poll already reports exit; genuine heartbeat regression verifies descendant stop. Windows departed-parent descendant termination remains unverified: parent-only PID cannot prove tree cleanup when inherited pipe reader survives, so retain uncertainty/ownership rather than false acknowledgement. Normal live-parent Windows taskkill remains exact-CI required.
- Computer assignment-only redaction missed quoted JSON credentials, marked whitespace values and short Bearer strings. Redact quoted values completely before any clipping and recognize short marked Bearer values, independently of both owner budgets. Genuine command tests include JSON values containing spaces and resource budgets0. Never publish raw output prefixes when capture stops mid-credential.

### AF-MEM-138 — install Windows descendant ownership before executing code
- PID/tree cancellation cannot reliably recover a Windows descendant after its parent has already exited. Prepared current-lifecycle repair creates the command with CREATE_SUSPENDED, assigns an unnamed non-inheritable Job with KILL_ON_JOB_CLOSE and no breakaway flags, then resumes its primary thread through documented Toolhelp/OpenThread/ResumeThread APIs. Any assignment/resume failure stops the suspended process and denies launch. Job activeprocesscount0 is required before termination acknowledgement; failed job handle cleanup retains ownership. Native execution remains explicit opt-in, container isolation remains mandatory/default; Job Objects are not a new sandbox and do not promise containment of WMI-created processes.
- Keep Job ownership when command exits but descendants remain, including descendants with DEVNULL pipes. Return background_descendants after owned cleanup rather than falsely complete. Sole holder process termination closes its private Job handle in Windows; genuine abrupt-holder regression must prove child removal. Four native Windows fixtures are explicitly NOT_EXECUTED on Linux, not API mocks or native acceptance.
- Ship windows_job.py beside computer_service.py and require its presence in Windows package build. Source/module execution paths both need tested import resolution. Kernel32 signatures use pointer-sized handles and explicit32bitDWORD/64bit accounting fields. Do not infer ABI/runtime success from Python parse or Linux regressions.
- Primary API references: https://learn.microsoft.com/en-us/windows/win32/procthread/job-objects ; https://learn.microsoft.com/en-us/windows/win32/api/jobapi2/nf-jobapi2-assignprocesstojobobject ; https://learn.microsoft.com/en-us/windows/win32/procthread/suspending-thread-execution ; https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-resumethread ; https://learn.microsoft.com/en-us/windows/win32/api/winnt/ns-winnt-jobobject_extended_limit_information . Prepared source needs exact-SHA genuine Windows CI before this lesson is considered runtime-resolved.

### AF-MEM-139 — GUI ownership spans request phases and survives failed cancellation
- Bind authenticated GUI execution identity through a trusted HTTP header before sending requests; GET carries no invented body. Model payload cannot choose the nonce or suppress unsafe-effect uncertainty. One root ownership spans screen-before/action/screen-after/UIA phases: cancellation prevents any later phase from starting. Confirmed worker termination does not reverse already performed input effects; unsafe action cancellation remains uncertain and nonretryable.
- A spawn-importable bootstrap waits on a private parent Event. Assign the actual Windows worker to its owned Job before opening that Event, so no GUI effects precede ownership. Package the bootstrap beside the service. Keep worker, queue and Job ownership when stop fails; only confirmed cleanup removes them. Test the Event with observed bootstrap readiness, not an arbitrary sleep.
- Fault injection must target the selected ownership backend. Patching the old PID-tree terminator cannot simulate failed Windows Job termination. Use the actual Job terminate method, prove the genuine worker/process remains live and retained, restore the real method and prove retry cleanup. Native Job API regressions are distinct from fake lifecycle unit tests.
- Actual Godot/HTTP/service/spawn tests can use an explicitly isolated GUI-shaped worker fixture without invoking a desktop. This proves nonce propagation, MasterStop, transport cancellation and uncertainty, not physical screen/input acceptance. Never expose a production fixture flag or label those software tests native desktop acceptance.

### AF-MEM-140 — UIA coverage must distinguish budgets, failed elements and exact fit
- Capture private owner UIA item/window/per-window-control/name/type/automation-ID and screen/UIA-worker budgets before HTTP. GET transports that immutable snapshot through an authenticated JSON header; model-provided policy is overwritten. Zero means no operational ceiling, finite nonnegative validation remains mandatory. UIA platform library enumeration may itself materialize data: returned-result budgets are not a promise to bound provider internal allocation.
- Detect overflow by observing an actual extra element, not by declaring an exactly full result truncated. Mark shortened fields and failed element extraction separately; empty failed extraction stays partial. Redact complete marked values before clipping fields, including unlimited policy. Preserve UIA reasons and failure counts in combined screen response.
- A worker can publish its result but stay alive. Zero deadline must keep awaiting completion and remain cancellable; do not invent a post-response100ms timeout. Poll joins under short lifecycle-lock sections and release the lock between polls. Cancellation wins the timeout classification race and remains nonretryable. Test with a genuine spawned worker that queues a result then hangs.

### AF-MEM-141 — result retention must never erase input idempotency
- Fixed schema text/key/click/scroll/duration caps prevent owner-raised or unlimited policy. Retain syntax/finite-number/click-progress/coordinate/auth/idempotency/failsafe boundaries while validating operational sizes against a trusted captured owner snapshot before any worker effects. Include the same snapshot in verification phases and allow zero worker deadline only with proven owned cancellation.
- Evicting an action result must not authorize replay. Keep consumed action identities separately from retained detailed results, return a nonretryable uncertain deduplicated terminal error when a prior result is unavailable, and never relaunch that input. Positive owner identity capacity refuses new IDs before effects instead of forgetting old IDs; zero means no capacity ceiling. Unexpected attempted-action exceptions also consume the identity. Process restart durability is a separate acceptance concern; this service-local repair must not be described as durable cross-restart idempotency.
- Genuine spawned GUI-shaped worker launch counts prove exact/raised/zero action policy and non-replay after result eviction/capacity denial. They do not exercise physical keyboard/mouse effects. Invalid NaN/infinite/negative duration and clicks0 remain rejected even with unlimited operational policy.

### AF-MEM-142 — recurrence of executor outage; distinguish primary Core assertion from watchdog
- References AF-MEM-123/129/130: after actual source publication, CreateProcess again reports exec-server transport disconnected/recovery timed out after25s. Read-only pwd recovery attempts stall and are bounded/abandoned; GitHub connector remains usable. This does not prove filesystem loss, source-test failure or rejected permission. Do not request redundant permission, fabricate unpublished source or promise background continuation. Restore the actual checkout and reconcile fresh remote SHA before additional local-source testing.
- A Windows Core HTTP fixture first failed its success-response assertion at core_progress_http_smoke.gd:20. The subsequent30s subprocess.TimeoutExpired and WinError10053 are secondary observations; they do not establish why the actual progress response failed. Cause UNKNOWN. Add complete controlled fixture-response and server delivery-timing evidence before any repair; do not increase the250ms stall/180ms total/no-progress budgets or blindly rerun.
- Godot assertion failure can leave a SceneTree test running until its external watchdog. Prepared fixture repair preserves all10 boolean acceptance conditions and every deadline, but emits actual controlled response and explicitly quits1/returns immediately on a failed check. Successful completion still requires all checks and exits0 only at the end. Server tracing records fixture event byte counts/delivery timing and terminal exception type, never credentials or user content. Source review is not Godot/Python execution; exact Windows CI remains required while local executor is unavailable.


### AF-143 — Stream directories before allocating entry arrays
Use owned scandir iterators rather than os.walk/listdir arrays for quota-aware tree and snapshot preflight. Stop after actual extra eligible entry, distinguish exact fit from overflow, close every nested iterator on generator cancellation/error. Test genuine directories with instrumented iterators that refuse reads beyond cap+1; test nested closure, unsafe entries and legacy trusted owner propagation. This bounds enumeration, not shutil.copytree growth/race behavior. Executor recovery retained checkout/runtime; missing latest-venv python symlink repaired without reinstalling preserved packages; outage root cause unknown.

### AF-144 — Independent trusted API budgets and capacity semantics
Per-request and aggregate body budgets belong to trusted startup configuration, never client headers or model payload. Zero disables only its own ceiling; positive aggregate can be smaller than request ceiling. Reject a body larger than the aggregate budget permanently413; only concurrent contention is temporary503/Retry-After. Track and release reservations even when ceilings are zero; finally must release on parser error and task cancellation. After response start propagate the original failure without sending a second response. Real ASGI chunk/concurrency tests and actual FastAPI startup wiring complement deployment source-contract checks. Negative/invalid startup budgets fail visibly rather than silently clamp. Preserve authentication, account mail and public rate boundaries.


### AF-145 — Zero retention must bypass destructive SQL and migration slicing
Conversation zero retention cannot use [-0:] accidentally or max(20,value), and SQL OFFSET0 would delete all rows. Explicitly bypass trimming/deletion for zero; positive owner count keeps exact latest entries, context zero maps to SQLite LIMIT-1 ordered history. Real migration/restart/owner-isolation and authenticated-chat tests prevent fixed call-site context24 from overriding trusted configuration. Preserve120/24 existing defaults; increasing retention cannot restore previously deleted data. The maintenance subsystem may avoid private-data pruning while a separate positive conversation retention policy deletes rows; do not conflate them.

### AF-146 — Independent API transport/content budgets preserve security and cleanup
Trusted startup upload bytes/recovery TTL/analysis HTTP deadline preserve existing defaults and support independent zero: guard positive byte ceilings, bypass startup stale pruning at TTL0, map deadline0 to requests timeout=None. Still remove completed/failed analysis transport files in finally; temporary uploads are not user Knowledge. Exercise actual local HTTP200/500 and requests timeout propagation rather than only mocked analysis. Pydantic content max_length=None removes max only, preserving min-length/normalized scores/auth/token validation. Full authenticated HTTP must reject client metadata/header attempts to raise startup validators. Latest Computer-only venv lacked requests when reused for API; collection failure is NOT_EXECUTED until dependencies installed and real tests pass, not a product regression. Audit JSON uses classifications, not rules; validate schema before scripted edits and preserve narrow exact statements.


### AF-147 — Enforce bridge wire-frame cap before parsing final receive
A loop checking prior buffer size can accept an oversized final recv containing newline. Bound recv to remaining owner frame bytes+1 and verify first complete frame size before UTF8/JSON; positive frame budget counts terminal newline. Exact-size frame succeeds, overflow explicit, zero reads until complete frame/remote closure. Genuine TCP fixtures check received-byte accounting and immutable requestID even with zero budgets. TCP chunk65536 is read granularity, not total response ceiling. Connect/read owner deadlines independent; socket timeout0 would be nonblocking, so map unlimited zero to None and reject negative/nonfinite policy.

### AF-148 — Preserve discovery responsiveness while honoring explicit owner provider policy
Unconfigured Ollama discovery retains call-site health/default deadlines, avoiding silent latency changes. Explicit trusted startup discovery policy overrides old internal health argument; chat deadline separately owned. Map zero to requests None; validate finite nonnegative fractional seconds. Real HTTP tags/chat tests capture Session.send options while executing actual network I/O; mocked localCore/Knowledge fallback tests remain separate and mandatory. No claim that removing synchronous deadlines creates cancellation or bounds provider-internal response allocation.


### AF-149 — Distinguish operational unlimited zero from empty-allocation zero
File backend cache bytes0 must bypass eviction, while requests/subprocess operation deadline0 becomes None. Update private UI minimum, saved-value validation, environment export and backend together; actual Godot save/reload/env and full Python module reload prevent half-applied settings. Do not globally reinterpret numeric zero: archive listing0 hides listing, internal text allocation0 means zero characters, positive sampling intervals/dimensions provide progress/representable allocation. Outer analysis deadline remains a separate owner control. Exercise actual cache files/HTTP/ffmpeg; stubbed transcript proves no recognition quality. Reportlab missing prevented PDF fixture setup; install test dependency and actually reexecute instead of marking failed setup as product regression or PASS. Native OCR skip remains NOT_PASS.

### AF-150 — Named-budget regex can falsely close an appended fixed cap
An audit regex matching any VISION_TIMEOUT_SECONDS occurrence classified an appended FIXED_LIMIT17 as owner-adjustable. A preserved adversarial test exposed this false closure. Replace broad names with reviewed full-statement anchored alternatives (22 File statements); unknown changes/trailing executable code remain unclassified. Classification must not infer that all neighboring limits are adjustable simply because one variable is owned.

### AF-151 — Explicit CI file lists do not automatically execute new regression modules
API workflow individually lists test files and test paths. New actual TCP/HTTP provider regression was published but absent from its list. Add both push/PR filters and actual pytest command; retain all existing coverage. Prior green API job cannot prove omitted fixture execution, even when its source dependency triggered the workflow. Verify selection and require exact new CI before acceptance; local tests remain separate evidence.

### AF-152 — Snapshot preflight does not constrain bytes copied after source growth
On317d0151 preflight/postflight surrounded shutil.copytree: source growth could materialize over owner limits before final rejection, and error cleanup could delete an already-existing destination. Stream actual entries and cap+1 file reads, reject before writing excessive bytes, verify opened regular-file identity against fresh lstat, use nofollow/nonblocking where available to avoid replacement symlink/FIFO, and create destination exclusively. Only clean a destination created by this operation; restore owned read-only directory/file permissions for cleanup and report cleanup failure explicitly. Preserve file modes/time and reverse directory metadata restoration. Actual growth, replacement, FIFO, collision, executable metadata and injected cleanup failure fixtures pass locally; Windows native evidence still required. This does not prove race-free parent path traversal or a transactional source view.

### AF-153 — Real ffmpeg regression requires matching CI and release test dependency
Exact317 File job112736667994 failed importing imageio_ffmpeg although production requirements pin0.6.0. Both explicit voice-ci and release Python dependency lists omitted it. Add matching pin rather than skip actual extraction fixture or misattribute missing setup as product failure. Reexecuted identical File test selection locally66PASS/2subtestsPASS; exact new CI remains necessary. Check all explicit test environments when adding fixtures using existing production dependencies.

### AF-154 — Empty-plan benchmark must retain transport/parser evidence
Core Windows317 run37604527306 artifact11473964567 passed20/21 required scenarios, failed simple_planning with steps0/checks0; performance and HTTP progress passed. Artifact had no model output/parser diagnostic, so transport/JSON/schema cause cannot be determined and remains UNKNOWN. Record transport flag, content length/hash and validated plan failure category without raw private response. Reject wrong-shaped steps explicitly; do not synthesize fallback steps or weaken required quality score. Genuine unavailable/malformed/wrong-shaped/empty/valid plan fixtures pass; a subsequent real Core run is required to establish cause and acceptance.

### AF-155 — Persist long local batch completion evidence across idle gaps
Executor PTY session identifier disappeared after an owner idle gap while checkout remained intact; original completion result was unavailable and not counted. Reexecuted coherent Computer batch once with stdout saved to scratch and explicit completion record:148PASS/6SKIP. Persist completion evidence before relying on a transient session handle; absence of a handle is not proof of test success or a product failure.

### AF-156 — Windows timestamp nofollow support differs from Linux
Exact8658 Computer Windows job112838541302/run37634934668:122PASS/2SKIP/4FAIL at os.utime(...follow_symlinks=False), Python3.11.9 raises NotImplementedError. Linux passed, so its green result did not prove portability. Check os.supports_follow_symlinks, reject freshly observed symlink/reparse destination before timestamps, and omit unsupported argument on that platform. Genuine capability-unavailable fixture performs real copy/timestamp update; native Windows reexecution required. Keep known parent-path race limitation visible rather than imply equivalent atomic nofollow on Windows.

### AF-157 — Default retrieval counts and caller overrides are separate policies
Memory recent12/search8 and Agent recent8 were fixed despite existing owner agent/chat retrieval counts. Give independent private default controls preserving12/8/8. Default-call sentinel-1 resolves owner count, zero owner ceiling maps full eligible collection; explicit caller0 still means empty and positive overrides retain precedence. Genuine20record lexical/merged/recent/Knowledge fixtures plus actual Agent prompt check2/15/unlimited; no new memory schema or scoring change. A new fixture inferred a ternary from Variant loop value and Godot refused parsing; explicit expected:int fixes fixture typing, initial parse failure not counted as execution.

### AF-158 — Unlimited Knowledge chunk/batch/search must retain progress and records
Previously KnowledgeStore chunk1800/stream batch131072/structured flush2048/search6 were fixed. Private owner controls preserve defaults; positive chunk splitting checks progress, chunk0 bypasses splitting, batch0 bypasses intermediate flush but final flush remains mandatory. Structured operation state captures write/chunk policy once; later owner changes apply next operation. Default search0 retains all sorted matches and bypasses intermediate top-K pruning, explicit search0 stays empty; positive caller override preserved. Actual JSONL import/removal,20hit retrieval, 3000Unicode text and real streaming batches1/32/0 validate preservation. Text import intentionally strips outer whitespace; FileAccess EOF can add blank terminal line, so compare normalized text rather than wrongly demand byte-identical importer output. An initial fixture assertion failed for that documented normalization; fixed fixture, not runtime text policy. Godot assertion can leave SceneTree alive: bound local smoke process and inspect marker, do not treat exit absence as PASS.

AF-154/AF-156 evidence reconciliation: actual8658 Core Windows job112838645833 succeeded with unchanged21/21 quality criterion; earlier317 empty-plan cause remains UNKNOWN, not claimed repaired by diagnostics. Actualea254f8 ComputerWindows job112840901226SUCCESS confirms capability-aware timestamp repair on Windows; keep portability fixture and unsafe destination checks.

### AF-159 — Voice zero is independent startup policy, not destructive cache eviction
Voice cache0 previously deleted every cached WAV/sidecar; Say text16000/path4096 and micqueue128 were fixed. Frozen trusted startup policy validates nonnegative integer independently; zero removes Pydantic max only, skips cache eviction, and selects Queue(maxsize0) unbounded. Private persisted Godot settings export into portable and managed launch; labels explicitly require restart. Actual file pairs, production request definitions over HTTP, full path identity, production queue callback and health accounting validate exact/raised/0. Queue overflow increments a visible dropped-chunk count, not false full audio capture. Lightweight fixtures execute production consumers but do not load acoustic models/microphone; packaging/native/quality evidence remains separate. Local venv lacked NumPy; collection failure not executed until2.2.6 installed. Explicit new test lists require FastAPI/Pydantic/httpx in ordinary/release test environments, preserve existing checks.

### AF-160 — Continuation punctuation must not overwrite spoken source characters
Actual small-budget speech regression exposed _as_continuation replacing final character with comma on full chunks. Old positive80clause fixture did not detect loss for long unbroken text. Reserve comma space by reducing cut and retaining the character in remaining; full1char chunks omit comma. Zero returns all prepared speech, negative invalid, explicit positive1/2/20/100 preserved without old48floor. Tests require all source letters survive and every positive chunk fits, plus existing clause/quality regression. Voice helper normalizes text/whitespace by design; comma punctuation is synthesized, not source content. DSP FFT256..2048/hop64 clamps remain explicitly unclassified, not silently accepted as owner controls.

### AF-161 — Candidate ownership starts before the first await; cancellation survives every operation
An availability await before _running allowed a second tournament to overwrite shared execution state. Acquire ownership before inference availability, release on every rejection/completion, and forward the existing Work caller guard through ToolRegistry. Poll candidate_control so Work cancellation is checked without generating additional action IDs. Strict bool permission and expired required Callable fail closed. Before/after model/tool guards discard stale success; after an already-started tool report effects_may_have_occurred instead of claiming rollback. Actual entry overlap/delayed availability/model/tool fixtures exercise production guard flow with only platform/dependency seams replaced; this is not native source-verification proof. Fake AI creates detached Android/Desktop runtime children: free these explicitly in the fixture; rerun must confirm clean exit.

### AF-162 — Structured inference routing must recognize the actual planning prompt
117Windows quality20/21 planning had successfultransport/emptycontent while engine generated768tokens. Production planner's Верни ТОЛЬКО JSON did not match desktop strict-structured detection, so existing reasoning_effort:none was not selected. Align to existing explicit Верни только строгий JSON contract; captured production-prompt fixture tests actual detector and ordinary prose negative case. This repairs a confirmed routing mismatch; hidden-reasoning exhaustion remains an inference until real native gate passes, not proven solely by fake model. Keep21/21, owner tokenbudget and normal conversational reasoning.

### AF-163 — Sandbox input policy does not waive filesystem or execution boundaries
Fixed Pydantic command64/cwd1024/writepath1024/task4000 are operational request ceilings. Independent trusted startup integer settings and private Godotexport preserve defaults;0maxNone retains fullidentity, not silent clipping. Mandatory nonemptycommand/path, auth, containment and degradedexecution opt-in remain. Actual small-budget HTTPwrite/workspacefixtures verify full acceptedpayload; longpath schema fixture proves requestidentity only, not Windowsfilesystem path support. OSerrors are not proof of an owner ceiling. Invalidnegative/fraction/nonASCII startup policy fails closed.

### AF-164 — Self-primary source contracts follow control wrappers into the real inference call
Candidate cancellation wrapper moved ai.chat out of proposal/review. Three50b472CIjobs failed a stale direct-call string expectation even though production still uses same local-only AI. Update contract to follow proposal/review -> guarded helper -> ai.chat, assert before/after control ordering and retain compatibility prohibition. Actual71Python and genuineGodot guardsPASS; do not discard local-only requirement or labelCI failure as Voice runtime defect.

### AF-165 — Strict JSON planning must not inherit the terse answer budget
Exact Windows Core runs 37658688995, 37662749554, 37664243520 and 37665766523 passed 20/21 quality scenarios; only `simple_planning` failed. JSON wrapper recovery and engine `response_format=json_object` alone did not close the gap. The fixed synthetic tea-planning response in run 37665766523 began with a valid objective and eight steps, then stopped in the middle of the `risks` key (518 characters). Production `_is_explicit_terse_request` matched its broad Russian `только с` marker inside the planner instruction `Верни только строгий JSON`, selecting the short owner `terse_max_tokens` budget. Correct routing computes strict structure first and excludes it from terse classification; strict JSON gets owner `chat_max_tokens`, while explicit short prose keeps its prior budget. Genuine Godot payload fixture asserts both classification and actual `max_tokens`; unchanged real Windows Core run 37667509560 on d79726ce96d09d5e5c577832226aa30fd7b0f114 passed 21/21 quality and performance, including seven planner steps. The bounded response excerpt exists only in the fixed synthetic benchmark artifact; ordinary runtime diagnostics retain length/hash without private content. Prevent recurrence by testing production prompt-to-payload routing, not only the planner parser or a fake direct model result. Status: RESOLVED for this exact Windows Core gate; final same-SHA package/device/release acceptance still required.

### AF-166 — File health probes and PDF render scale are independent owner limits
Windows File Intelligence fixed optional Ollama and Voice health GET deadlines at 1.5 seconds and PDF OCR render scale at 2.0, despite the existing private owner file-limit settings. Added persisted/visible millisecond health deadlines and PDF render-scale percentage (defaults 1500/1500/200). Trusted startup exports exact nonnegative integer values; zero maps health timeout to requests timeout=None and removes only the scale ceiling. The independent PDF render pixel budget still bounds ceil(width*scale)*ceil(height*scale) before native rendering. Render scale joins cache identity, so changing it cannot reuse stale OCR output. Actual monkeypatched requests calls prove default/25/2500/zero deadlines; render fixtures prove 2.0/1.5/zero and invalid values, cache identity changes; Godot owner persistence/export and Settings contract pass. Ordinary File Intelligence suite25PASS and listing-owner suite6PASS only after running outside Windows sandbox temporary-file restriction. Initial sandbox run produced WinError5 on `.ci`/AppData temp paths, not a code assertion failure; rerunning full suites with authorized local temp access gives genuine PASS. Keep this distinction in release evidence. Native Windows package/installed application gate on the new exact SHA remains required.

AF-166 fixture follow-up: exact2c36b25 Core/Voice run37680867860 File Intelligence job passed66 and failed two AST-extracted cache-key fixtures with NameError MAX_PDF_RENDER_SCALE_PERCENT. Those tests supply production `_cache_key` globals manually; the new cache-identity field was omitted from both fixture namespaces. Keep scale in production cache identity. Source fixtures now enumerate referenced uppercase globals from production `_cache_key.__code__.co_names` and copy available service values, so future owner cache factors cannot be silently omitted. Both exact fixture suites11PASS locally. The native Linux job must rerun on the corrected SHA. Local full six-module CI-shaped run66PASS/2FAIL for unrelated Windows-only symlink privilege and newline expectations in Project Index; those two remain NOT_EXECUTED as successful Linux tests until CI passes, and do not justify weakening project-index behavior.

### AF-167 — File client HTTP deadlines belong to the owner independently of backend work

Windows File Intelligence backend health, tree and cache requests used fixed client-side HTTPRequest deadlines4/60/30 seconds. Backend operation policies cannot override a shorter client timeout. Persist independent private owner settings with those defaults; zero maps directly to Godot HTTPRequest.timeout0.0 while request cancellation, positive backend analysis deadline and retry behavior remain separate. A real Godot route probe exercises health/tree/cache call sites and an actual HTTPRequest object captures default/raised/zero property values. The repo owner audit must distinguish these tested owner deadlines from caller defaults, read-chunk granularity and retry cadence; exact filename120 and error-detail4000 truncations remain visible for later review. On local Windows, pytest inherited cp1252 and unrelated UTF-8 source-contract reads raised UnicodeDecodeError; set PYTHONUTF8=1 and rerun the whole selected suite, then count only the rerun (36PASS). Native exact-SHA CI and package checks remain required.

### AF-168 — Project Index backend work can outlast fixed client HTTP deadlines

Project Index Windows client used fixed HTTPRequest deadlines5/900/60/30seconds for health/index/search/management. Existing owner source/query/result budgets do not control these client waits. Add four independent owner resource keys with identical defaults, visible through the generic Settings resource panel; zero sets HTTPRequest.timeout0.0, leaving backend SQLite lock timing and owner traversal budgets separate. Genuine Godot route probe covers health/index/search/symbols/status/clear and real HTTPRequest objects at default/raised/zero; private config save/read rejects negative and fractional values. Exact audit review classifies only tested timeout assignment and structural request construction/retry cadence, preserving HTTP error-detail4000 as unclassified. Local Godot smoke and38 Python owner/audit contracts PASS. Native exact-SHA package/integration evidence remains required.

### AF-169 — Delayed first synthetic SSE event can consume the entire tiny stall fixture budget

Exact100979f Windows Core Benchmarks run37687398923 failed before the model benchmark: check_1 got `no_progress`, http0, generated0, while server accepted the request but sent zero events before the client closed after its synthetic250ms deadline. This does not establish a model/quality failure. The fixture slept60ms before the first true prompt-progress event, so Windows runner connection/request scheduling had less than190ms for setup; local restricted sandbox reproduction stayed in HTTPClient connecting status3 through259ms, while authorized local loopback completed the entire unchanged fixture. Keep the accepted production Core no-progress/total/byte/cancellation semantics and the 250ms/180ms synthetic deadlines. Send the first actual progress event immediately after the server accepts the request, then retain each60ms subsequent cadence, including a final sleep so the total duration remains long enough for the180ms total-budget negative case. `AURORA_CORE_HTTP_SERVER_START` plus per-event final trace record first-event timing. Authorized local genuine HTTP fixture passed all success, heartbeat, duplicate, total, byte, malformed, truncated, HTTP-error and cancellation cases with first event at0ms. Exact new Windows CI including actual bundled Core21/21 remains the acceptance gate. A default-sandbox local loopback connection stall is environment evidence, not a product assertion; use authorized local network for genuine HTTP verification.

### AF-170 — Computer parent watchdog must confirm death by process handle

Confirmed source defect at2947eb1: the Windows Computer watchdog searched for a PID as a substring of `tasklist` output and treated any tasklist timeout or exception as parent death, then cancelled owned processes and exited. A transient probe failure could therefore end a healthy service, while another process with a matching PID substring could mask a dead parent. Replace text parsing with OpenProcess(SYNCHRONIZE) and nonblocking WaitForSingleObject on the exact PID; declare death only for a signaled handle or ERROR_INVALID_PARAMETER. Access denial, wait failure and unexpected probe exceptions remain unknown and trigger a later retry, never immediate cancellation. Declare pointer-size ctypes signatures explicitly to preserve 64-bit handles; close every acquired handle. POSIX ESRCH means absent, EPERM means alive, other OSError means unknown. Deterministic fake API and watchdog tests cover all states; actual Windows current-process handle smoke covers the native call. A standard pytest temp path inside the Windows sandbox can fail before tests start; use a workspace `--basetemp` and report the rerun, not the setup error, as test evidence. Native exact-SHA Windows CI remains required before acceptance.

### AF-171 — Android Maven dependency resolution can fail on one identical-SHA attempt

At exact bc4a709 Android Plugin run37694499001 attempt1, Gradle `:plugin:checkDebugAarMetadata` could not resolve `org.tukaani:xz:1.10`, `com.github.junrar:junrar:8.0.0` and `org.apache.poi:poi:5.5.1` from configured Google Maven/Maven Central/JitPack. Predecessor4979ba0 passed the same Android plugin source/workflow/dependencies; `git diff` between SHAs found no Android source or workflow change. One failed attempt alone does not establish absent artifacts or a product defect. Rerun only the failed job on the identical bc4a709 SHA before changing dependency pins or tests; attempt2 completed SUCCESS, including AAR build and exported library verification. External repository availability/cache behavior is a plausible but unconfirmed root cause. Preserve the red attempt in evidence and require the green identical-SHA retry; if repeated, inspect repository HTTP/Gradle resolution diagnostics before modifying build inputs.

### AF-172 — Queue caller capacity cannot exceed an internal list slice

At V1.5 head64ec5dd, `CoreCandidateQueue(max_items=250)` with201 persistent on-disk entries reported only200 through `list(250)` and `status()`. `_trim_if_needed()` used that truncated list and could permit over-capacity when the configured capacity exceeded200. Root cause was a fixed200 slice inside the generic queue list method, independent of its caller-provided limit. Remove that internal ceiling while preserving positive list semantics, candidate source validation, promotion allowlist, authentication scopes and the public FastAPI route's existing `le=200` pagination contract. The201-entry persisted regression must assert the true count and full-queue rejection when max_items201 has no terminal item. Focused candidate plus owner-audit modules37PASS, authorized local API gateway/privacy/hardening52PASS before publication; exact-SHA API CI remains required. A source-level audit classification must not hide unrelated candidate-source byte and default retention limits.

### AF-173 — Restricted Windows loopback failure is not an API assertion verdict

During the AF-172 local API breadth run at head64ec5dd, the default Windows sandbox gave `WinError 10013` connecting to a genuine `127.0.0.1` File Intelligence fixture. The run was interrupted after early failures and is not a product PASS/FAIL verdict; the queue change does not touch that HTTP path. Repeating the unchanged three API modules with authorized local loopback and workspace `--basetemp` produced52PASS. This is the local permission boundary already described in AF-MEM-051 and AF-169, not evidence to remove the HTTP test or weaken its deadline. Preflight or request loopback capability for genuine local server fixtures, then count only the completed rerun; keep exact CI as the release gate.

### AF-174 — Candidate source budget must agree across client, queue and API schema

The private `candidate_source_bytes` setting already controlled Core candidate creation, but `CoreCandidateSubmitter` independently rejected every source over 1 MiB. The API queue separately fixed decoded source at 1 MiB and Base64 at 2 MiB; `CoreCandidateSubmitRequest` also fixed encoded text at 2 MiB. Raising the owner setting therefore could never work end to end. The client now reads its owner byte setting before opening source and checks again after read. The API queue reads a separate trusted startup `AURORAFOX_CORE_CANDIDATE_SOURCE_BYTES` (default 1 MiB), derives the Base64 preflight ceiling from that byte budget, and rejects negative/fractional/malformed operator values. Zero removes only the candidate-specific cap. The request model retains nonempty input but no smaller fixed cap; independent global HTTP body middleware, auth scopes, signed-update/evidence/hash checks and target allowlist remain. A genuine >2 MiB source and encoded payload >2 MiB cover default, raised, zero and environment paths; Godot smoke covers owner default/raised/zero at the submitter. On local Windows, direct server import initially failed because its default SQLite location was outside the test workspace; setting `AURORAFOX_USER_DIR` to the test directory fixed fixture isolation, then candidate/audit42PASS and full selected API82PASS with authorized local loopback. Native exact-SHA Godot/API CI remains required.

### AF-175 — Independent Core promotion must share the trusted source budget

After AF-174, the client and API could accept an owner/operator-authorized Core candidate over 1 MiB, but `build/verify_core_candidate_bundle.py` still rejected it at a fixed 1 MiB. The independent promotion workflow therefore could reject a valid queued candidate solely for size. Keep the independent verifier and trusted-main checkout. Its byte budget now reads `AURORAFOX_CORE_CANDIDATE_SOURCE_BYTES` from trusted process configuration (default 1 MiB), and the workflow passes the trusted repository variable with the same default. Zero removes only that candidate-specific size cap. A candidate manifest cannot override it; SHA, allowlist, source growth, dangerous primitive, clean-baseline review and signed release gates remain. A >2 MiB fixture failed before repair at the missing `max_source_bytes` parameter, then covered default, raised, zero, trusted environment and malformed values. On Windows, the initial fixture wrote text with platform newline conversion, so byte hashes and exact size differed from the intended LF source; write fixture UTF-8 bytes explicitly for cross-platform integrity tests. First sandbox fixture also hit WinError5 on path resolution; use authorized local temp access before judging the product. Full local promotion/queue/owner suite55PASS after fixture correction; exact native CI is still required.

### AF-177 — Secrets-only release preflight must exclude every publication route
- Confirmed at2d447772: release publish guard's recovery OR accepted workflow_dispatch+publish_run_id even with secrets_only=true. Normal preflight without recovery stayed skipped; no unintended publication was observed. Obsolete substring assertions failed after recovery syntax changed, and this test module was absent from explicit Release Identity CI selection.
- Place the secrets-only veto outside the entire tag/recovery OR. Retain successful Windows/Android dependency gates for ordinary tag publication and existing publish-only recovery. Test actual job expressions across288 event/preflight/recovery/tag/job-result combinations using a restricted AST boolean/comparison interpreter that rejects unsupported syntax. The original guard demonstrably allows the preflight+recovery case and the repaired guard rejects it.
- Add this regression to both CI path filters and the actual pytest invocation; old green jobs did not execute it. Local focused49PASS and YAML parse establish source repair; exact published CI remains required. No private key or token values needed to reproduce the condition defect.

### AF-178 — Standalone Core contract must follow the canonical release version
- Confirmed on V1.5.0.0 candidate `a9f914a06c01fb01c0d919c0fddb440f391b1a38`: Research Quality run37774645310, Core/Voice run37774645315 and Integration Gate run37774645336 failed because `tests/test_standalone_core_contract.py` pinned `V1.4.1.1`/Android100007 and Android export `version/name="1.4.1.1"`. Other bundled model/package checks passed; this was not a Core runtime or signing failure.
- Root cause: the test encoded one historical release version even though `build/set_version.ps1` is the canonical version-last mechanism. Reverting the correct V1.5 metadata or weakening the bundled-model checks would hide the defect.
- Fix/prevention: derive the four-part version and Android versionCode from `project/version.json`; require consistency with project.godot, updater manifest, changelog and Android export, plus a versionCode newer than published V1.4.1.1/100007. Preserve pinned model bytes/hash, package id, bundled weights and other assertions. Local standalone module12PASS after repair; full exact-SHA CI and signed post-version release gates still required.
- Status: RESOLVED. Exact source SHA `b0341f5133e8a9cf03bfd4e0a57fad08c1f236bf` passed Research Quality run37775672814, Core/Voice run37775672920, Integration Gate run37775672786 and all other23 PR workflows; signed branch Release run37775738190 also completed SUCCESS for Core/Windows/Android with publication SKIPPED.

### AF-179 — Updater repair must locate Windows artifacts under the downloaded directory tree
- Confirmed on merged V1.5 candidate `12c3145e22b5197300c5f5f6a709eb15e053a0b4`: Windows Package CI run37807556056 uploaded `AuroraFox-Windows` successfully, but follow-on Updater Repair Validation run37816833961 failed in `Restore packaged files as build/windows` with `Windows portable artifact is missing`. Its lookup only examined the download root. The upload includes files from both `dist/` and `artifacts/`, so preserving their common directory layout can place package files below the download root; the precise archive entry layout was not independently inspected.
- Fix/prevention: search recursively beneath the downloaded artifact directory for the exact canonical version and require exactly one portable and setup file, including in the Linux repair-publication job. Missing or duplicate files fail closed. Preserve the packaged trust-root fingerprint check, V1.2/V1.3 in-place smokes, signed-floor eligibility and stable-latest isolation. Test flat, nested, missing and duplicate layouts locally, then require the actual follow-on workflow on final main SHA before publication.
- Status: FIX_PENDING_EXACT_CI. A successful Windows upload alone does not establish that the downstream repair gate passed.
- PR104 first exact `release-identity` run37820253742 failed 27PASS/1FAIL because `test_update_backward_compat.py` pinned the old root-only `source=` spelling. Update this structural assertion to require recursive exact-version selection, uniqueness and use of the selected path. Keep the signed-floor and stable-latest assertions; rerun exact CI before accepting the workflow change.
