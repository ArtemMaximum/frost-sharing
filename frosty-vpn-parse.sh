#!/bin/bash

# Путь к вашей локальной папке репозитория
REPO_DIR="$HOME/projects/utils/frost-sharing"

# ВПИСЫВАЙТЕ СЮДА ТО ИМЯ, КОТОРОЕ УВИДЕЛИ НА ШАГЕ 1 (например: subscription.txt)
FILE_NAME="index.txt"

# ВАША НАВЕК ЗАФИКСИРОВАННАЯ ССЫЛКА НА ПОДПИСКУ
SUB_URL="https://frosty-sub.com/sub/e07c7b07-2b15-4096-b841-6f645df3030b"

# Проверка папки репозитория
if [ ! -d "$REPO_DIR/.git" ]; then
    echo "Локальный репозиторий не найден. Клонирование из GitHub..."
    rm -rf "$REPO_DIR"
    git clone https://github.com "$REPO_DIR"
    if [ $? -ne 0 ]; then
        echo "Ошибка клонирования репозитория." >&2
        exit 1
    fi
fi

echo "Скачивание конфигурации..."

# Делаем запрос, полностью маскируясь под клиент Happ/Hiddify
JSON_RESPONSE=$(curl -sL \
  -A "Happ/1.0.0 (Android; 13) sing-box/1.9.0" \
  -H "Accept: application/json" \
  -H "X-App-Version: 1.0.0" \
  "$SUB_URL")

if [ -z "$JSON_RESPONSE" ]; then
    echo "Ошибка: Сервер вернул пустой ответ." >&2
    exit 1
fi

# Временный файл для промежуточной сборки ссылок vless://
TEMP_RAW_LINKS=$(mktemp)

# Извлекаем чистые текстовые строки ссылок vless://
if [[ "$JSON_RESPONSE" == "{"* ]]; then
    echo "$JSON_RESPONSE" | jq -r '.outbounds[] | select(.type | in({"vless":1,"vmess":1,"shadowsocks":1,"trojan":1})) | ._uri // empty' > "$TEMP_RAW_LINKS"
else
    CLEAN_B64=$(echo "$JSON_RESPONSE" | tr -d '\r\n ')
    echo "$CLEAN_B64" | openssl enc -base64 -d -A 2>/dev/null | grep -v "127.0.0.1" > "$TEMP_RAW_LINKS"
fi

if [ ! -s "$TEMP_RAW_LINKS" ]; then
    echo "Ошибка: Не удалось извлечь конфигурации серверов." >&2
    rm -f "$TEMP_RAW_LINKS"
    exit 1
fi

# ПЕРЕЗАПИСЫВАЕМ СУЩЕСТВУЮЩИЙ ФАЙЛ: Кодируем текстовый список обратно в Base64 одной строкой
TARGET_FILE="$REPO_DIR/$FILE_NAME"
openssl enc -base64 -e -A -in "$TEMP_RAW_LINKS" -out "$TARGET_FILE" 2>/dev/null
echo "" >> "$TARGET_FILE"

rm -f "$TEMP_RAW_LINKS"

# Пушим обновленный файл на GitHub
echo "Публикация изменений на GitHub Pages..."
cd "$REPO_DIR" || exit 1

# Синхронизируемся с облаком перед коммитом
git pull origin main --rebase 2>/dev/null

git add "$FILE_NAME"

# Проверяем реальные изменения контента
if ! git diff-index --quiet HEAD --; then
    git commit -m "Auto-update subscription: $(date '+%Y-%m-%d %H:%M:%S')"
    git push origin main
    echo "Успешно! Существующий файл в репозитории обновлен и отправлен в облако."
else
    echo "Конфигурации не изменились. Обновление не требуется."
fi
