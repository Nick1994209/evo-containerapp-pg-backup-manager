# PostgreSQL backup manager

Минимальная основа Alpine 3.23 + клиент PostgreSQL 18 и корневые TLS-сертификаты.
Без PostgreSQL-сервера, Python, Bash и планировщика. Фактический размер зависит
от версий пакетов.

## Сборка и публикация

```sh
docker build --platform linux/amd64 -t nvkorolkov-public.cr.cloud.ru/pg-backup-manager:v0.0.1 .
docker push --platform linux/amd64 nvkorolkov-public.cr.cloud.ru/pg-backup-manager:v0.0.1
```

Для push нужна авторизация в registry (`docker login nvkorolkov-public.cr.cloud.ru`).
Если Docker не поддерживает `push --platform`, используйте обычный `docker push`:
образ уже собран для `linux/amd64`.

## Backup и restore

Задайте `DATABASE_URL` в окружении (URI `postgresql://user:password@host:5432/db?sslmode=require`
или libpq conninfo). Спецсимволы в компонентах URI должны быть percent-encoded.
Можно вместо URL передать стандартные переменные PostgreSQL или использовать `.pgpass`.
Секреты в образ не копируются.

```sh
mkdir -p backups

docker run --rm --platform linux/amd64 \
  -e DATABASE_URL -v "$PWD/backups:/backups" \
  nvkorolkov-public.cr.cloud.ru/pg-backup-manager:v0.0.1 backup backup.dump

# DATABASE_URL теперь должен указывать на существующую целевую базу.
docker run --rm --platform linux/amd64 \
  -e DATABASE_URL -v "$PWD/backups:/backups:ro" \
  nvkorolkov-public.cr.cloud.ru/pg-backup-manager:v0.0.1 restore backup.dump
```

Поддерживаются `.dump` (custom, сжатие PostgreSQL), `.sql`, `.sql.gz`.
`dump` — синоним `backup`. После имени файла можно передать параметры утилиты,
например `backup schema.dump --schema-only` или `restore backup.dump --clean --if-exists`.
Последняя команда явно удаляет восстанавливаемые объекты. По умолчанию удаления нет.
Не переопределяйте параметры формата, файла и транзакции через дополнительные опции.

Backup не перезаписывает существующий файл и публикует результат только после успеха.
Каталог должен поддерживать hard links. `.sql.gz` требует места для несжатого SQL:
при backup — рядом с результатом, при restore — в `/tmp`.
Restore выполняется одной транзакцией и завершается ошибкой при сбое;
параллельное восстановление и `--create` в этом режиме не поддерживаются.
Владельцы и ACL не восстанавливаются. Для специальных сценариев доступны напрямую
`pg_dump`, `pg_restore`, `psql` как первая команда контейнера.

Основная версия клиента должна быть не ниже версии исходного сервера. Для восстановления в PostgreSQL
с более низкой версией, чем у клиента, совместимость не гарантируется: лучше использовать клиент той же
основной версии, что и целевой сервер. Другую версию можно выбрать через
`--build-arg PG_MAJOR=17`, если пакет доступен в выбранной Alpine.
Это логическая копия одной базы: роли кластера, tablespaces, WAL/PITR сюда не входят.

Можно запускать контейнер с `--user "$(id -u):$(id -g)"`, если пользователь имеет
права записи в каталог backups. Для read-only rootfs добавьте `--read-only --tmpfs /tmp`.

Документация: [pg_dump](https://www.postgresql.org/docs/18/app-pgdump.html),
[пакет Alpine](https://pkgs.alpinelinux.org/package/v3.23/main/x86_64/postgresql18-client).
