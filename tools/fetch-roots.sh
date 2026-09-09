#!/bin/sh
# Снимает цепочку сертификатов с api.yclients.com и кладёт якоря
# в Resources/certs.
#
# Зачем это нужно
# ---------------
# Хранилище корневых сертификатов в iOS 6 собрано в 2012 году и с тех пор
# не пополнялось. Всё, что выпущено позже — ISRG Root X1 (Let's Encrypt,
# 2015), GlobalSign R6, нынешние российские корни, — этой системе неизвестно.
#
# Пока сервер присылает цепочку, которая замыкается на какой-нибудь старый
# корень, всё работает само, и каталог Resources/certs может быть пустым.
# В день, когда перестанет, приложение молча перестанет открывать что-либо:
# в журнале будет «Цепочка отвергнута», и больше ничего.
#
# Этот скрипт готовит якоря заранее. Проверка в YCHttp от них не слабеет:
# сначала спрашивается система, и только если она отказала, добавляются эти.
#
# Что он делает
# -------------
# Забирает то, что сервер присылает в рукопожатии, и складывает всё, кроме
# самого листа, в Resources/certs как .der. Оттуда их подхватит сборка —
# в коде нет списка имён, берутся все файлы подряд.
#
# Чего он **не** делает: не скачивает корень из интернета. Верхнее звено
# присланной цепочки обычно промежуточное, а не корневое, и его срок жизни
# — год-полтора. Скрипт печатает, кем оно выдано; настоящий корень надо
# взять с сайта удостоверяющего центра и положить сюда же:
#
#     openssl x509 -in root.pem -outform der -out Resources/certs/root.der
#
# Отпечатки печатаются затем, чтобы положенный файл можно было сверить,
# не доверяя тому, кто его положил.
#
#     sh tools/fetch-roots.sh
#     sh tools/fetch-roots.sh some.other.host
#
# Внимание: в WSL сеть бывает недоступна — тогда запускать это надо там,
# откуда api.yclients.com открывается.
set -e

HOST="${1:-api.yclients.com}"
PORT=443

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CERTS="$ROOT/Resources/certs"

mkdir -p "$CERTS"

echo "Спрашиваем $HOST:$PORT…"

CHAIN="$(mktemp)"

# -showcerts отдаёт всё, что прислал сервер; </dev/null закрывает ввод,
# иначе openssl ждёт, что в соединение что-нибудь напишут.
if ! openssl s_client -connect "$HOST:$PORT" -servername "$HOST" -showcerts \
        </dev/null 2>/dev/null > "$CHAIN"; then
	echo "Не удалось соединиться с $HOST:$PORT" >&2
	rm -f "$CHAIN"
	exit 1
fi

if ! grep -q "BEGIN CERTIFICATE" "$CHAIN"; then
	echo "Сервер не прислал ни одного сертификата — соединение не состоялось" >&2
	rm -f "$CHAIN"
	exit 1
fi

# Разбираем поток на отдельные файлы: awk считает блоки BEGIN/END.
WORK="$(mktemp -d)"

awk -v out="$WORK" '
	/BEGIN CERTIFICATE/ { n++; keep = 1 }
	keep                { print > sprintf("%s/%02d.pem", out, n) }
	/END CERTIFICATE/   { keep = 0 }
' "$CHAIN"

echo
echo "Прислано звеньев: $(ls "$WORK" | wc -l | tr -d ' ')"
echo

INDEX=0

for pem in "$WORK"/*.pem; do
	INDEX=$((INDEX + 1))

	SUBJECT="$(openssl x509 -in "$pem" -noout -subject | sed 's/^subject= *//')"
	ISSUER="$(openssl x509 -in "$pem" -noout -issuer | sed 's/^issuer= *//')"
	UNTIL="$(openssl x509 -in "$pem" -noout -enddate | sed 's/^notAfter=//')"
	PRINT="$(openssl x509 -in "$pem" -noout -fingerprint -sha256 | sed 's/^.*=//')"

	echo "  $INDEX. $SUBJECT"
	echo "     выдан:  $ISSUER"
	echo "     до:     $UNTIL"
	echo "     SHA-256 $PRINT"

	# Лист — это сертификат самого узла; якорем он быть не может и не должен:
	# он меняется каждые несколько месяцев.
	if [ "$INDEX" -eq 1 ]; then
		echo "     (лист — не кладём)"
		echo
		continue
	fi

	NAME="$(openssl x509 -in "$pem" -noout -subject \
		| sed 's/^.*CN *= *//; s/,.*$//; s/[^A-Za-z0-9]\{1,\}/_/g' \
		| tr "[:upper:]" "[:lower:]")"

	[ -n "$NAME" ] || NAME="anchor_$INDEX"

	openssl x509 -in "$pem" -outform der -out "$CERTS/$NAME.der"

	echo "     → Resources/certs/$NAME.der"
	echo
done

# Самоподписанное верхнее звено — это и есть корень; тогда добирать нечего.
TOP="$(ls "$WORK"/*.pem | tail -1)"

TOP_SUBJECT="$(openssl x509 -in "$TOP" -noout -subject | sed 's/^subject= *//')"
TOP_ISSUER="$(openssl x509 -in "$TOP" -noout -issuer | sed 's/^issuer= *//')"

if [ "$TOP_SUBJECT" = "$TOP_ISSUER" ]; then
	echo "Верхнее звено самоподписано — это корень, добирать нечего."
else
	echo "Верхнее звено выдано:"
	echo "    $TOP_ISSUER"
	echo
	echo "Это корневой сертификат, и в цепочке его нет. Возьмите его на сайте"
	echo "удостоверяющего центра и положите рядом:"
	echo
	echo "    openssl x509 -in root.pem -outform der -out Resources/certs/root.der"
	echo
	echo "Без него якорями останутся промежуточные — работает, но их меняют"
	echo "раз в год-полтора, и тогда сборку придётся повторить."
fi

echo
echo "Готово. Сложено в Resources/certs; пересоберите пакет."

rm -rf "$WORK" "$CHAIN"
