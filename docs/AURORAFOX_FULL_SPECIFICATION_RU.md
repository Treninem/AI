# ЕДИНОЕ ТЕХНИЧЕСКОЕ ЗАДАНИЕ AURORAFOX

Ты продолжаешь разработку существующего проекта **AuroraFox**.

Не создавай новый проект с нуля. Сначала изучи существующий код, текущую архитектуру, память, обучение, систему мутаций, обновления, Windows-клиент, Android-клиент, локальные модели, текущие API, БД и тесты.

После аудита интегрируй описанную ниже архитектуру в существующий проект.

Основной домен уже зарегистрирован:

**aurorafox.ru**

Главная схема:

```text
AuroraFox Windows
        ↕
    aurorafox.ru
        ↕
   REG.RU VPS 24/7
        ↕
AuroraFox Android
```

Но это не три независимые AuroraFox.

Это должна быть **единая распределённая AuroraFox с общей серверной инфраструктурой**, отдельной персональной памятью каждого пользователя и синхронизацией между его устройствами.

---

# 1. ГЛАВНАЯ ЦЕЛЬ

Реализовать архитектуру:

```text
Windows ↔ REG.RU ↔ Android
```

где:

**REG.RU VPS**:

- работает 24/7;
- является центральным узлом;
- хранит серверное состояние;
- хранит пользовательские аккаунты;
- хранит серверную копию памяти;
- синхронизирует устройства;
- хранит чаты;
- хранит проекты;
- управляет файлами;
- управляет очередью задач;
- управляет обучением;
- управляет worker-узлами;
- хранит результаты мутаций;
- управляет версиями;
- выполняет обновления;
- создаёт резервные копии.

**Windows-ПК**:

- полноценный клиент;
- хранит локальную копию памяти своего пользователя;
- работает offline;
- является основным вычислительным worker;
- выполняет тяжёлое обучение;
- создаёт мутации;
- выполняет тестирование кандидатов;
- использует CPU/GPU локального ПК.

**Android**:

- полноценный мобильный клиент;
- чат;
- голос;
- история;
- файлы;
- проекты;
- уведомления;
- управление AuroraFox;
- синхронизация через сервер.

---

# 2. ДОМЕНЫ

Использовать:

```text
aurorafox.ru
api.aurorafox.ru
ws.aurorafox.ru
files.aurorafox.ru
update.aurorafox.ru
```

Назначение:

```text
api.aurorafox.ru
REST API

ws.aurorafox.ru
WebSocket

files.aurorafox.ru
файлы

update.aurorafox.ru
версии и обновления
```

Настроить:

- DNS;
- HTTPS;
- WSS;
- автоматическое получение TLS-сертификатов;
- автоматическое продление сертификатов;
- Nginx либо Caddy;
- reverse proxy;
- health-check.

Все поддомены могут вести на один VPS.

---

# 3. СЕРВЕРНАЯ АРХИТЕКТУРА

На REG.RU VPS должны работать:

```text
Reverse Proxy
AuroraFox API
AuroraFox WebSocket
Authentication Service
Database
Memory Service
Sync Service
File Service
Task Queue
Worker Manager
Evolution Manager
Update Service
Backup Service
Monitoring
```

По возможности использовать:

```text
Docker
Docker Compose
```

Но если существующая архитектура AuroraFox использует другой рабочий способ — интегрировать без бессмысленной полной переделки.

После перезагрузки VPS все критические сервисы должны автоматически запускаться.

---

# 4. МНОГОПОЛЬЗОВАТЕЛЬСКАЯ СИСТЕМА

AuroraFox должна быть многопользовательской.

Недопустимо, чтобы после установки приложения разные люди попадали:

- в один диалог;
- в одну память;
- в один аккаунт;
- в одну историю;
- в одни проекты.

Каждый пользователь должен иметь:

```text
user_id
profile
memory
conversations
messages
projects
files
settings
devices
sessions
personalization
sync state
```

Схема:

```text
AuroraFox Server
│
├── User A
│   ├── Memory
│   ├── Chats
│   ├── Files
│   ├── Projects
│   ├── Devices
│   └── Settings
│
├── User B
│   ├── Memory
│   ├── Chats
│   ├── Files
│   ├── Projects
│   ├── Devices
│   └── Settings
│
└── Guest C
    ├── Memory
    ├── Chats
    └── Settings
```

Все пользовательские данные должны быть привязаны к:

```text
user_id
```

---

# 5. ПЕРВЫЙ ЗАПУСК

При первом запуске показать:

```text
AuroraFox

[ Войти ]

[ Создать аккаунт ]

[ Продолжить как гость ]
```

Регистрация не должна быть обязательной для первого знакомства с приложением.

---

# 6. РЕГИСТРАЦИЯ

Основной способ регистрации:

```text
Email + пароль
```

Регистрация:

```text
Имя
Email
Пароль
Повтор пароля

[ Создать аккаунт ]
```

После регистрации:

1. создать уникальный `user_id`;
2. создать профиль;
3. создать пользовательское пространство памяти;
4. зарегистрировать устройство;
5. создать безопасную сессию;
6. отправить подтверждение email;
7. начать синхронизацию.

Email должен быть уникальным без учёта регистра.

---

# 7. ДОПОЛНИТЕЛЬНЫЕ СПОСОБЫ ВХОДА

Архитектура должна позволять добавить:

```text
Google
Apple
Telegram
VK
Passkey / WebAuthn
```

При этом AuroraFox не должна зависеть от стороннего поставщика.

Главный идентификатор:

```text
user_id
```

Один пользователь может иметь несколько методов авторизации:

```text
Account
├── Email
├── Google
├── Telegram
├── VK
└── Passkey
```

Не создавать автоматически отдельный аккаунт при каждом новом методе входа, если можно безопасно привязать метод к существующему аккаунту.

---

# 8. ПАРОЛИ

Никогда не хранить пароль:

- открытым текстом;
- в логах;
- в Git;
- в `.env`;
- в БД в обратимо зашифрованном виде.

Использовать:

```text
Argon2id
```

или другой современный безопасный алгоритм.

Реализовать:

- проверку пароля;
- смену пароля;
- восстановление;
- одноразовый reset-token;
- срок действия token;
- отзыв старых recovery token.

---

# 9. СЕССИИ

Использовать:

```text
Access Token
+
Refresh Token
```

Реализовать:

- expiration;
- rotation refresh token;
- revoke;
- список активных сессий;
- отзыв отдельного устройства;
- обнаружение повторного использования старого refresh token.

На Android хранить секреты в защищённом системном хранилище.

На Windows — использовать защищённое хранилище ОС, если доступно.

Пароль не сохранять для автоматического входа.

---

# 10. ГОСТЕВОЙ РЕЖИМ

Обязательно реализовать:

```text
Продолжить как гость
```

Каждый гость получает собственный уникальный:

```text
guest_id
device_id
created_at
```

Недопустимо:

```text
user_id = guest
```

для всех.

Должно быть:

```text
Guest A ≠ Guest B ≠ Guest C
```

В гостевом режиме доступны:

- чат;
- история;
- локальная память;
- настройки;
- несколько чатов;
- разрешённые локальные файлы;
- базовый функционал AuroraFox.

Гостевой режим строить прежде всего как:

```text
local-first
```

---

# 11. ПРЕВРАЩЕНИЕ ГОСТЯ В АККАУНТ

Если человек сначала использовал AuroraFox как гость, а затем регистрируется, предложить:

```text
Сохранить данные гостевого профиля
```

Перенести:

- чаты;
- память;
- проекты;
- настройки;
- файлы;
- локальные знания;
- историю.

Схема:

```text
Guest
↓
Create Account
↓
New user_id
↓
Migration
↓
Registered User
```

Миграция должна быть транзакционной.

При ошибке исходный гостевой профиль не удалять.

Не создавать дубликаты при повторной синхронизации.

---

# 12. ИЗОЛЯЦИЯ ПОЛЬЗОВАТЕЛЕЙ

Каждый запрос должен определять пользователя из проверенной сессии.

Нельзя доверять:

```text
user_id
```

полученному от клиента.

Плохо:

```text
GET /memory?user_id=123
```

Правильно:

```text
Access Token
↓
Server Authentication
↓
Authenticated User
↓
user_id
↓
DB Filter
```

Даже если пользователь вручную подставит ID чужого:

- чата;
- файла;
- проекта;
- памяти;

сервер не должен вернуть данные.

Ожидаемый результат:

```text
403
```

или:

```text
404
```

---

# 13. ПАМЯТЬ

Разделить:

```text
AuroraFox Core Memory
```

и:

```text
User Personal Memory
```

Глобальная память ядра может содержать:

- системные знания;
- улучшения движка;
- версии;
- общие навыки.

Память пользователя:

- личные диалоги;
- предпочтения;
- проекты;
- файлы;
- персональные знания;
- историю;
- персонализацию.

Персональная память User A никогда не должна стать памятью User B.

---

# 14. ЦЕНТРАЛЬНАЯ ПАМЯТЬ

На REG.RU хранится серверная копия памяти пользователя.

Windows-ПК при наличии интернета поддерживает актуальную локальную реплику.

Синхронизировать:

```text
memory
knowledge
conversations
projects
settings
skills
training results
version metadata
sync metadata
```

Не передавать каждый раз всю базу целиком.

Использовать инкрементальную синхронизацию.

Каждая синхронизируемая сущность должна иметь:

```text
id
user_id
revision
created_at
updated_at
origin_device
checksum
```

где применимо.

---

# 15. WINDOWS — ЛОКАЛЬНАЯ КОПИЯ

Windows хранит рабочую локальную копию.

Логически:

```text
AuroraFox/Data/
├── memory
├── knowledge
├── conversations
├── projects
├── training
├── mutations
├── models
└── sync
```

Если существующая структура проекта уже есть — использовать её, а не создавать дублирующую без необходимости.

---

# 16. OFFLINE-FIRST

Если интернет пропал:

```text
Windows AuroraFox
```

не должна переставать работать.

Все изменения сохраняются локально.

Создать persistent queue:

```text
sync_queue
```

После восстановления интернета:

1. определить последнюю синхронизированную revision;
2. получить изменения с сервера;
3. отправить локальные изменения;
4. обнаружить конфликты;
5. разрешить конфликты;
6. подтвердить запись;
7. удалить подтверждённые события из очереди;
8. проверить целостность.

При аварийном завершении очередь не терять.

---

# 17. КОНФЛИКТЫ

Например:

Windows:

```text
Project A → Aurora
```

Android:

```text
Project A → Fox
```

Сервер должен обнаружить конфликт revision.

Не использовать простое слепое:

```text
last write wins
```

для критичных объектов без анализа.

Предусмотреть:

- revision;
- timestamps;
- origin_device;
- историю изменений;
- правила разрешения конфликтов.

Для сложных конфликтов можно сохранять обе версии до безопасного разрешения.

---

# 18. REAL-TIME СИНХРОНИЗАЦИЯ

Использовать WebSocket.

События:

```text
message.created
message.updated
conversation.updated
memory.updated
project.updated
file.created
task.updated
worker.status
training.started
training.completed
mutation.completed
release.available
```

Если Windows и Android одного пользователя онлайн — изменения отображаются почти сразу.

После обрыва WebSocket:

- reconnect;
- exponential backoff;
- reconciliation через API.

WebSocket нельзя считать единственным источником истины.

---

# 19. ANDROID

Android использует сервер.

Основные функции:

- чат;
- голос;
- загрузка файлов;
- камера;
- история;
- проекты;
- память;
- настройки;
- уведомления;
- управление AuroraFox.

Тяжёлое обучение на Android по умолчанию не выполнять.

---

# 20. НЕСКОЛЬКО УСТРОЙСТВ

Один пользователь может иметь:

```text
Windows PC
Android Phone
Android Tablet
Second PC
```

Все они используют один аккаунт и одну персональную память.

В профиле:

```text
Мои устройства
```

Для устройства хранить:

```text
device_id
user_id
platform
name
client_version
created_at
last_seen
status
worker_capabilities
```

Пользователь может:

```text
Завершить сессию
Удалить устройство
```

После этого credentials устройства становятся недействительными.

---

# 21. WINDOWS КАК WORKER

Windows-ПК автоматически регистрируется как worker.

Сервер знает:

```text
online/offline
CPU
RAM
GPU
GPU memory
client version
busy/idle
current task
last heartbeat
```

Схема:

```text
REG.RU
↓
Task Queue
↓
Windows Worker
↓
Execution
↓
Result
↓
REG.RU
```

Если ПК выключен:

```text
heavy task
↓
persistent queue
```

Когда ПК включается:

```text
worker online
↓
sync
↓
task receive
↓
execution
```

---

# 22. ОБУЧЕНИЕ

Тяжёлое обучение преимущественно выполнять на Windows-ПК.

Сервер:

- формирует задания;
- управляет очередью;
- назначает worker;
- хранит результаты;
- контролирует выполнение.

ПК:

- анализ;
- обучение;
- benchmarks;
- тяжёлые вычисления;
- GPU-задачи;
- мутации.

---

# 23. МУТАЦИИ

При цикле эволюционного улучшения AuroraFox должна создавать:

```text
3–10 кандидатов
```

Пример:

```text
Stable
├── Mutation 01
├── Mutation 02
├── Mutation 03
├── Mutation 04
├── Mutation 05
└── ...
```

Количество кандидатов определяется:

- доступной RAM;
- CPU;
- GPU;
- сложностью задачи;
- временем выполнения.

Но должно быть:

```text
минимум 3
максимум 10
```

если цикл мутаций действительно запущен.

---

# 24. МУТАЦИИ ДОЛЖНЫ БЫТЬ РЕАЛЬНЫМИ

Недопустимо считать мутацией:

- случайное изменение цифры;
- запись в лог;
- изменение фиктивного параметра;
- копию без различий;
- mock;
- dummy implementation.

Кандидаты должны реально отличаться:

- алгоритмом;
- стратегией;
- параметрами;
- кодом;
- конфигурацией модели;
- обработкой памяти;
- поиском;
- логикой принятия решений;

в зависимости от задачи.

---

# 25. ТУРНИР МУТАЦИЙ

Все кандидаты должны получить одинаковый тестовый набор.

Порядок:

```text
Create Candidates
↓
Run Tests
↓
Benchmark
↓
Score
↓
Tournament
↓
Best Candidate
↓
Regression Tests
↓
Integration Tests
↓
Security Tests
↓
Candidate Release
```

Пример:

```text
Mutation 01 = 82
Mutation 02 = 91
Mutation 03 = 87
Mutation 04 = 95
```

Победитель:

```text
Mutation 04
```

Но это ещё не Stable.

---

# 26. STABLE И CANDIDATE

Рабочая версия не должна уничтожаться экспериментом.

Использовать:

```text
Stable
Candidate
```

Схема:

```text
Stable A
↓
Candidate B
↓
isolated environment
↓
tests
↓
health check
↓
regression
↓
promotion
↓
Stable B
```

Если Candidate B падает:

```text
Stable A
```

остаётся работать.

---

# 27. BLUE/GREEN DEPLOYMENT

Для серверной части желательно:

```text
Aurora Blue
Aurora Green
```

Например:

```text
Blue = Stable 1.4
Green = Candidate 1.5
```

Проверить Green.

Только после успешного прохождения:

```text
Proxy
Blue → Green
```

Если Green ломается:

```text
Green → Blue rollback
```

---

# 28. АВТОМАТИЧЕСКИЙ ROLLBACK

Rollback обязателен при:

- crash;
- startup failure;
- health-check failure;
- regression;
- DB migration failure;
- повреждении данных;
- критическом росте ошибок.

---

# 29. РАСПРЕДЕЛЕНИЕ РЕСУРСОВ

REG.RU выполняет:

- API;
- WebSocket;
- DB;
- память;
- синхронизацию;
- пользователей;
- очередь;
- координацию;
- лёгкие задачи;
- мониторинг.

Windows выполняет:

- тяжёлое обучение;
- 3–10 мутаций;
- benchmarks;
- GPU;
- тяжёлые тесты;
- локальные модели.

---

# 30. ФАЙЛЫ

Схема:

```text
Client
↓
files.aurorafox.ru
↓
File Service
↓
Storage
↓
Processing
↓
Chat / Memory
```

Хранить:

```text
file_id
user_id
conversation_id/project_id
filename
mime
size
checksum
created_at
storage_key
```

Проверять MIME, а не доверять расширению.

Ограничить размер.

Проверять опасные файлы согласно доступным возможностям проекта.

---

# 31. ОБНОВЛЕНИЯ

Разделить версии:

```text
AuroraFox Server
AuroraFox Windows
AuroraFox Android
```

Endpoint:

```text
update.aurorafox.ru
```

Хранить:

```text
server_version
windows_version
android_version
minimum_supported_version
release_channel
checksum
```

Обновление Windows не должно удалять:

- память;
- настройки;
- локальную БД;
- модели;
- sync queue.

---

# 32. BACKUP

Автоматически резервировать:

- БД;
- память;
- пользователей;
- настройки;
- метаданные файлов;
- конфигурацию;
- критичные данные Evolution Manager.

Обязательно проверить не только создание backup, но и реальное восстановление.

ПК является дополнительной репликой пользовательской памяти, но не является единственным backup.

---

# 33. SECURITY

Обязательно:

```text
HTTPS
WSS
authentication
authorization
rate limiting
input validation
session revoke
device revoke
secure password hashing
secure token storage
```

Не хранить секреты в Git.

Использовать:

```text
.env
.env.example
```

Но реальный `.env` не коммитить.

---

# 34. ADMIN

Не смешивать:

```text
User
Admin
System
Worker
```

Права выдаёт только сервер.

Нельзя получить admin, просто отправив:

```json
{
  "role": "admin"
}
```

---

# 35. EMAIL

Реализовать:

- подтверждение email;
- восстановление пароля;
- email verification token;
- recovery token;
- expiration;
- одноразовое использование.

API не должен позволять удобно определять, существует ли конкретный email.

---

# 36. ПЕРСОНАЛЬНАЯ ПАМЯТЬ И ОБУЧЕНИЕ

У каждого пользователя отдельная персонализация.

Пример:

```text
User A
→ свои проекты
→ свои предпочтения
→ свои диалоги

User B
→ другие проекты
→ другие предпочтения
→ другие диалоги
```

Не использовать приватные пользовательские данные как общий источник обучения без соответствующего разрешения и архитектурного разделения.

Разделить:

```text
Core Evolution
```

и:

```text
User Personalization
```

---

# 37. УДАЛЕНИЕ АККАУНТА

Предусмотреть:

```text
Удалить аккаунт
```

Удаление одного пользователя не должно затрагивать других.

Архитектура должна позволять:

- удалить;
- обезличить;
- очистить файлы;
- удалить сессии;
- удалить устройства;
- удалить память;

в соответствии с принятой политикой.

---

# 38. БАЗОВАЯ СХЕМА БД

Не обязательно копировать буквально, но логика должна быть аналогичной:

```text
users
├── id
├── display_name
├── email
├── password_hash
├── email_verified
├── created_at
└── updated_at

auth_identities
├── id
├── user_id
├── provider
├── provider_subject
└── created_at

sessions
├── id
├── user_id
├── device_id
├── refresh_token_hash
├── expires_at
└── revoked_at

devices
├── id
├── user_id
├── platform
├── name
├── app_version
└── last_seen

conversations
├── id
├── user_id
└── ...

messages
├── id
├── conversation_id
├── user_id
└── ...

memory
├── id
├── user_id
├── revision
└── ...

projects
├── id
├── user_id
└── ...

files
├── id
├── user_id
└── ...

sync_events
├── id
├── user_id
├── device_id
├── revision
└── ...

tasks
├── id
├── user_id/system
├── worker_id
├── status
└── ...

workers
├── id
├── device_id
├── capabilities
└── ...
```

---

# 39. HEALTH И МОНИТОРИНГ

Обязательно:

```text
/health
/ready
/version
```

Логи:

- login;
- device connect;
- WebSocket;
- sync;
- task;
- training;
- mutation;
- tournament;
- deployment;
- rollback;
- errors.

Не выводить:

- пароль;
- access token;
- refresh token;
- recovery token;
- секреты.

---

# 40. ОБЯЗАТЕЛЬНЫЕ ТЕСТЫ СИНХРОНИЗАЦИИ

### TEST SYNC-01

Windows online + server online.

Изменение на Windows появляется на сервере.

---

### TEST SYNC-02

Android отправляет сообщение.

Сообщение появляется на Windows того же пользователя.

---

### TEST SYNC-03

Windows отправляет сообщение.

Сообщение появляется на Android.

---

### TEST SYNC-04

Выключить интернет Windows.

Создать данные.

Включить интернет.

Изменения синхронизируются.

---

### TEST SYNC-05

Windows offline.

Android создаёт сообщения.

Windows возвращается.

Сообщения появляются локально.

---

### TEST SYNC-06

Оборвать WebSocket.

После reconnect пропущенные события восстанавливаются.

---

# 41. ТЕСТЫ ПОЛЬЗОВАТЕЛЕЙ

### TEST USER-01

Создать:

```text
User A
User B
```

User A создаёт чат.

User B делает:

```text
GET /chats
```

Чат User A отсутствует.

---

### TEST USER-02

User B вручную подставляет ID чата User A.

Результат:

```text
403/404
```

---

### TEST USER-03

User A создаёт память.

User B не может её:

- прочитать;
- изменить;
- удалить.

---

### TEST USER-04

Создать Guest A и Guest B.

У них разные:

- guest_id;
- чаты;
- память.

---

### TEST USER-05

Guest создаёт данные.

Регистрируется.

Данные успешно мигрируют.

---

### TEST USER-06

После повторной синхронизации гостевые данные не дублируются.

---

### TEST USER-07

User A входит на Windows и Android.

Данные синхронизируются.

---

### TEST USER-08

User B онлайн одновременно.

Он не получает WebSocket-события User A.

---

### TEST USER-09

Отозвать Android-сессию.

Старый refresh token больше не работает.

---

### TEST USER-10

Password reset token нельзя использовать повторно.

---

# 42. ТЕСТЫ WORKER

### TEST WORKER-01

Windows регистрируется как worker.

Сервер видит:

```text
online
CPU
RAM
GPU
```

---

### TEST WORKER-02

ПК выключен.

Сервер создаёт тяжёлую задачу.

Задача остаётся в очереди.

---

### TEST WORKER-03

ПК включается.

Worker получает задачу.

Выполняет.

Отправляет результат.

---

# 43. ТЕСТЫ МУТАЦИЙ

### TEST EVO-01

Запустить настоящий цикл:

```text
3–10 mutations
```

Проверить, что кандидаты реально различаются.

---

### TEST EVO-02

Все кандидаты получают одинаковые тесты.

---

### TEST EVO-03

Определяется победитель.

---

### TEST EVO-04

Победитель проваливает regression.

Stable остаётся прежней.

---

### TEST EVO-05

Победитель проходит всё.

Становится новой Stable.

---

### TEST EVO-06

Новая версия падает после deployment.

Выполняется rollback.

---

# 44. BACKUP TEST

Создать backup.

Удалить/повредить тестовую БД в изолированном окружении.

Восстановить.

Проверить:

- пользователей;
- память;
- чаты;
- настройки;
- sync state.

---

# 45. ПЕРЕЗАГРУЗКА VPS

Перезагрузить сервер.

После запуска должны автоматически подняться:

- DB;
- API;
- WebSocket;
- queue;
- Evolution Manager;
- reverse proxy;
- monitoring.

---

# 46. НИКАКИХ ФИКТИВНЫХ ТЕСТОВ

Не считать систему рабочей, если тест проверяет только mock.

Нужны реальные integration и end-to-end сценарии:

```text
UI
↓
Client
↓
Network
↓
Server
↓
DB
↓
Memory
↓
Sync
↓
Other Client
```

---

# 47. НЕ ИСПОЛЬЗОВАТЬ ЗАГЛУШКИ КАК ФИНАЛЬНЫЙ РЕЗУЛЬТАТ

Недопустимы:

```text
TODO
pass
dummy
mock-only
hardcoded success
fake mutation
fake training
fake synchronization
```

Если временная заглушка нужна для разработки — перед финальным результатом заменить реальной реализацией.

---

# 48. СОВМЕСТИМОСТЬ СО СТАРОЙ AURORAFOX

Перед изменениями найти:

- память;
- updater;
- training;
- mutations;
- Evolution Manager;
- Android;
- Windows;
- локальные модели;
- API;
- DB;
- version system;
- тесты.

Не удалять рабочий функционал без необходимости.

Если требуется изменить БД:

```text
migration
```

Если меняется формат памяти:

```text
memory migration
```

Старые пользовательские данные должны сохраняться.

---

# 49. ПОРЯДОК РАБОТ

Выполнять по этапам:

```text
1. Audit
2. Database architecture
3. User accounts
4. Guest mode
5. Authentication
6. Server API
7. HTTPS/WSS
8. Windows sync
9. Offline-first
10. Android sync
11. Device management
12. Worker system
13. Task queue
14. Evolution Manager
15. 3–10 mutations
16. Tournament
17. Stable/Candidate
18. Rollback
19. Update system
20. Backup
21. Monitoring
22. End-to-end tests
23. Security tests
24. Final code audit
25. Repeat all tests
```

---

# 50. КРИТЕРИЙ ГОТОВНОСТИ

Если:

```text
1000 пользователей скачали AuroraFox
```

результат должен быть:

```text
User 0001 → свои чаты + память
User 0002 → свои чаты + память
User 0003 → свои чаты + память
...
User 1000 → свои чаты + память
```

а не:

```text
1000 пользователей → одна общая память
```

---

# 51. КОНЕЧНАЯ АРХИТЕКТУРА

```text
                         aurorafox.ru
                              │
                              ▼
                     REG.RU VPS 24/7
                              │
            ┌─────────────────┼─────────────────┐
            │                 │                 │
            ▼                 ▼                 ▼
          User A            User B            Guest C
            │                 │                 │
        ┌───┴────┐        ┌───┴────┐            │
        ▼        ▼        ▼        ▼            ▼
     Windows   Android  Windows   Android      Device
        │
        ▼
    Local Memory
        │
        ▼
 Windows Worker
        │
        ▼
 Training / Mutations
```

---

# 52. ПОВЕДЕНИЕ ПРИ ВЫКЛЮЧЕННОМ ПК

Если Windows-ПК выключен:

```text
REG.RU
+
Android
```

продолжают работать.

Тяжёлые задачи ждут worker.

---

# 53. ПОВЕДЕНИЕ БЕЗ ИНТЕРНЕТА НА ПК

Если Windows offline:

```text
AuroraFox Windows
↓
local memory
↓
local conversations
↓
local changes
↓
sync queue
```

После появления интернета:

```text
automatic reconciliation
↓
upload
↓
download
↓
conflict resolution
↓
synced state
```

---

# 54. ПОВЕДЕНИЕ ПРИ ВКЛЮЧЕНИИ ПК

```text
Windows starts
↓
connect REG.RU
↓
authenticate
↓
register worker
↓
sync memory
↓
sync conversations
↓
get server changes
↓
send local changes
↓
receive queued heavy tasks
↓
training/mutations
```

Всё должно происходить автоматически без ручного копирования памяти.

---

# 55. ГЛАВНЫЙ ПРИНЦИП

AuroraFox должна восприниматься пользователем как одна система:

```text
сервер = постоянно работающий центр
Windows = полноценная локальная версия + вычислительный узел
Android = мобильный клиент
```

При этом у каждого пользователя собственная персональная AuroraFox:

```text
один аккаунт
одна персональная память
много устройств
```

---

# 56. ФИНАЛЬНАЯ ПРОВЕРКА

Не объявляй задачу завершённой после написания кода.

После реализации обязательно:

1. запустить все unit-тесты;
2. запустить integration-тесты;
3. запустить end-to-end тесты;
4. выполнить security-тесты;
5. проверить два разных аккаунта;
6. проверить двух разных гостей;
7. проверить Windows + Android одного пользователя;
8. проверить offline;
9. проверить reconnect;
10. проверить worker;
11. проверить цикл 3–10 мутаций;
12. проверить tournament;
13. проверить regression;
14. проверить deployment;
15. проверить rollback;
16. проверить backup;
17. проверить восстановление;
18. перезапустить VPS;
19. повторить ключевые тесты;
20. выполнить финальный аудит кода.

Если тест не проходит:

```text
найти причину
↓
исправить
↓
повторить тест
```

Не скрывать непрошедшие тесты.

В финальном отчёте разделить:

```text
Проверено реально
```

и:

```text
Не удалось проверить из-за отсутствующего внешнего ресурса
```

Например если отсутствуют:

- доступ к REG.RU;
- DNS;
- SMTP;
- Android-устройство;
- GPU;
- production credentials.

Не утверждать, что непроверенная внешняя часть работает на 100%.

Готовым результат считается рабочая интегрированная AuroraFox, в которой сервер, Windows, Android, пользователи, гостевой режим, память, синхронизация, worker, обучение, мутации, тестирование и безопасные обновления действительно соединены между собой, а не существуют как отдельные неиспользуемые классы.
