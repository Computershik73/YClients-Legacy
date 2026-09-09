export THEOS ?= $(HOME)/theos

# 9.3 — последний SDK, где ещё живы заголовки эпохи iOS 5–6 и в котором есть
# срез armv7. Нижняя граница 6.0 — так просил заказчик; ниже опускаться нечем:
# api.yclients.com отвечает только по TLS 1.2, а Secure Transport умеет его
# начиная с iOS 5. То есть 5.1 технически возможна, но UIKit iOS 6 даёт
# UIRefreshControl и UICollectionView, и отказываться от них ради одной
# версии назад смысла нет.
TARGET := iphone:9.3:6.0

# armv7 покрывает всё от iPhone 3GS до iPhone 5; arm64 — всё, что новее.
ARCHS := armv7 arm64

# dpkg-deb отказывается паковать каталог с правами 777, а именно их выдаёт
# диску Windows подсистема WSL — chmod там ничего не меняет. Поэтому дерево,
# из которого собирается пакет, складывается в файловую систему Linux.
export THEOS_STAGING_DIR ?= /tmp/theos-yclients/_

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = YClients

##############################################################################
# Библиотека cYclients
##############################################################################
#
# Живёт отдельным репозиторием и является источником истины: здесь она не
# форкается, а копируется в vendor/ перед сборкой. Путь переопределяется:
#
#     make CYCLIENTS=/путь/к/cYclients
#
CYCLIENTS ?= $(CURDIR)/../cYclients

# Копия делается **на разборе makefile**, а не правилом before-all.
#
# Список файлов ниже нужен make уже в момент разбора — из него строятся
# правила компиляции. Правило, которое отработает позже, к этому моменту
# опоздает: на чистой выкачке vendor/ ещё нет, список получился бы пустым,
# и theos собрал бы приложение без единого вызова к API, ничего не сказав.
#
# cp -u сверяет время правки, так что обычная пересборка ничего не копирует.
_cyc_sync := $(shell mkdir -p vendor/cYclients/src && \
	cp -u "$(CYCLIENTS)"/cYclients.h vendor/cYclients/ 2>/dev/null; \
	cp -u "$(CYCLIENTS)"/partner_token.h vendor/cYclients/ 2>/dev/null; \
	cp -u "$(CYCLIENTS)"/src/*.c "$(CYCLIENTS)"/src/*.h vendor/cYclients/src/ 2>/dev/null; \
	echo ok)

ifeq ($(wildcard vendor/cYclients/partner_token.h),)
$(error Нет $(CYCLIENTS)/partner_token.h — см. ReadMe.md библиотеки: \
        токен партнёра берётся на yclients.com/appstore/developers)
endif

# Список набран руками, а не find, ровно ради одного исключения:
# curl_transport.c в сборку не идёт. Его место занимает src/net/YCTransport.m,
# который даёт ту же функцию curl_transport_exec поверх NSURLConnection —
# подробности там же, в шапке файла. Из-за этого libcurl приложению не нужен
# вовсе, а вместе с ним не нужна и его сборка под armv7/arm64.
CYC_SOURCES := cJSON.c structs.c companies.c categories.c services.c \
               users.c clients.c records.c staff.c stb_ds.c \
               custom_fields.c auth.c

YClients_FILES  = $(shell find src -name '*.m')
YClients_FILES += $(addprefix vendor/cYclients/src/,$(CYC_SOURCES))

##############################################################################
# Флаги
##############################################################################

YClients_CFLAGS  = -fobjc-arc -Wall -Wno-deprecated-declarations
YClients_CFLAGS += $(addprefix -I,$(shell find src -type d))
YClients_CFLAGS += -Ivendor/cYclients -Ivendor/cYclients/src

# Часть предупреждений выключена ради библиотеки — и только ради неё.
#
# Theos собирает с -Werror, а cYclients писалась под настольные системы,
# где clang 11 находит в ней своё:
#
#   missing-braces   таблицы default_field заполняются раскрытием X-макроса,
#                    и внутренних скобок у элементов нет — законный C,
#                    но повод для замечания;
#   format-security  адреса запросов собираются через sprintf с готовой
#                    строкой формата;
#   sign-compare     счётчики записей сравниваются со знаком.
#
# Ни одно из них не относится к нашему коду, а вместе они дают под двести
# строк на каждую сборку — за ними перестают быть видны собственные
# предупреждения, ради которых и стоит -Wall.
#
# Пофайлово это не выключить: theos сопоставляет %_CFLAGS с точным именем
# файла, шаблоны там не работают, а перечислять двенадцать файлов ради трёх
# ключей — хуже, чем поставить их на всю сборку.
YClients_CFLAGS += -Wno-missing-braces -Wno-format-security -Wno-sign-compare
YClients_CFLAGS += -Wno-unused-function -Wno-unused-variable

# Подменяет NSLog во всех файлах разом: всё, что уходит в системный журнал,
# попадает ещё и в Documents/yclients.log — оттуда его можно просто забрать
# с устройства через «Файлы» или iTunes. Подробности в src/YCLog.h.
YClients_CFLAGS += -include src/YCLog.h

# Журнал самой библиотеки (LOG в src/log.h) включается только с DEBUG;
# ERR пишется всегда. В готовой сборке не нужно ни то, ни другое.
ifeq ($(FINALPACKAGE),1)
YClients_CFLAGS += -DYC_NO_LOG
else
YClients_CFLAGS += -DDEBUG
endif

# Прокси для отладки — только в отладочной сборке.
#
# Включённый прокси снимает проверку сертификата: иначе перехватчик
# не заработает, он подменяет сертификат своим. То есть переключатель
# в настройках открывает соединение тому, кто стоит посередине, — а через
# него идут логин и пароль от YClients.
#
# Держать такой переключатель в готовой сборке незачем: там он был бы
# оружием против того, кто приложением пользуется, а не средством отладки.
# Поэтому в готовую сборку код прокси не попадает вовсе — не «есть,
# но выключен», а именно отсутствует; YCProxy отвечает на isCompiledIn
# отрицательно, и экран настроек показывает объяснение вместо переключателя.
#
# Нужен прокси в готовой сборке (обычно не нужен) — это делается явно:
#
#     make package ipa FINALPACKAGE=1 PROXY=1
#
ifneq ($(FINALPACKAGE),1)
YClients_CFLAGS += -DYC_PROXY
else ifeq ($(PROXY),1)
YClients_CFLAGS += -DYC_PROXY
endif

YClients_CFLAGS += -fvisibility=hidden

# Отладочная сборка без проверки сертификатов:
#
#     make package INSECURE_TLS=1
#
# Нужна ровно для одного — смотреть трафик перехватчиком (Charles и прочие).
# Тот подменяет сертификат своим, и честная проверка его не пропустит.
#
# По умолчанию выключено, и «выключено» здесь означает, что кода нет
# в бинарнике вовсе — он выброшен `#ifdef` ещё на разборе.
#
# Более аккуратный путь: положить корень перехватчика в Resources/certs/
# обычным .der — оттуда берутся все файлы подряд, и проверка остаётся
# включённой.
ifeq ($(INSECURE_TLS),1)
YClients_CFLAGS += -DYC_INSECURE_TLS
endif

##############################################################################
# OpenSSL
##############################################################################
#
# Своя криптография — не прихоть. На iPad 2 с iOS 6 вход в YClients просто
# висел до тайм-аута: системное хранилище корней там застыло в 2012 году
# (ни ISRG Root X1, ни новых GlobalSign в нём нет и не будет), а набор шифров
# той поры сервер 2026 года может не принять вовсе. Задать Secure Transport
# ни то, ни другое нельзя — подробности в src/net/YCTls.h.
#
# Берётся готовый набор срезов, собранный соседними проектами
# (Max-iOS/«АльтерВито», tools/build-openssl.sh). Путь переопределяется:
#
#     make SSL_OUT=/путь/к/out
#
SSL_OUT ?= $(firstword $(wildcard $(HOME)/altervito/out $(HOME)/lovit/out) $(HOME)/altervito/out)

ifeq ($(wildcard $(SSL_OUT)/armv7/openssl/lib/libssl.a),)
$(error Нет OpenSSL в $(SSL_OUT) — соберите его tools/build-openssl.sh \
        из Max-iOS или задайте SSL_OUT=/путь/к/out)
endif

# Заголовки и библиотеки берутся по текущему срезу: у armv7 и arm64 они
# разные, и подставить один набор на оба нельзя.
YClients_CFLAGS += -I$(SSL_OUT)/$(THEOS_CURRENT_ARCH)/openssl/include

YClients_LDFLAGS += $(SSL_OUT)/$(THEOS_CURRENT_ARCH)/openssl/lib/libssl.a
YClients_LDFLAGS += $(SSL_OUT)/$(THEOS_CURRENT_ARCH)/openssl/lib/libcrypto.a

YClients_FRAMEWORKS = UIKit CoreGraphics QuartzCore Security SystemConfiguration

# NSObject ищем по всем библиотекам, а не в той, где он лежит сегодня.
#
# До iOS 6 класс живёт в CoreFoundation, а не в libobjc. Нижняя граница
# у нас как раз 6.0, то есть формально привязка к libobjc верна — но она
# верна только для загрузчика ровно этой версии, а стоит она недорого:
# -U снимает привязку, и dyld ищет символ во всём, что загружено.
#
# Работает только вместе с tools/patch-sdk.sh, который убирает _NSObject
# из objc-classes в libobjc.tbd: пока символ в .tbd есть, компоновщик
# спокойно находит его и привязывает как обычно, и -U не делает ничего.
#
# Доллар закрывается дважды: \$$ превращается в \$ на разборе make, а уже \$
# доживает до ld как $ — между ними ещё оболочка, для которой $_NSObject это
# имя переменной.
YClients_LDFLAGS += -Wl,-U,_OBJC_CLASS_\$$_NSObject
YClients_LDFLAGS += -Wl,-U,_OBJC_METACLASS_\$$_NSObject

# Подпись — обеими сводками сразу, и это принципиально.
#
# ldid по умолчанию кладёт имя «YClients.<хеш>.unsigned» вместо имени пакета
# и снимает признак adhoc — то есть заявляет «подпись настоящая, спросите
# центр сертификации», хотя удостоверяющей части в файле нет вовсе.
#
#   -Cadhoc  признак «подпись сама себе удостоверение» — то, чем она и является;
#   -I…      имя, совпадающее с CFBundleIdentifier, — по нему система сверяет
#            подпись со связкой.
#
# Флага -H здесь нет намеренно. С -Hsha1 в подписи остаётся одна сводка SHA-1;
# это верно для iOS 8, но с iOS 11 система считает cdhash по SHA-256 и подпись
# без неё не принимает вовсе — приложение снимается при запуске, без записи
# в журнале падений. Без -H ldid кладёт обе: SHA-1 в основной слот и SHA-256
# в дополнительный. Одна подпись на весь ряд от iOS 6 до 12; проверяет это
# tools/check-macho.py.
YClients_CODESIGN_FLAGS = -Cadhoc -Iru.computershik.yclients -S

##############################################################################
# Срок жизни сборки
##############################################################################
#
# В двоичный файл зашивается время сборки, а YCExpiry отсчитывает от него
# неделю. Проверяется срок по времени сервера (YCClock), не по часам
# устройства: перевести часы — минутное дело, и замок на них ничего не стоит.
#
# Штамп кладётся отдельным заголовком, а не флагом компилятора, и вот почему.
# Общий CFLAGS сюда не годится: theos складывает имя каталога объектов
# из хеша всех флагов, и меняющееся число в них означало бы полную пересборку
# на каждый запуск. Флаг на один файл theos ищет по переменной с именем
# из полного пути к нему — писать такое имя вручную значит гадать. Заголовок
# же попадает в список зависимостей только того файла, который его включает.
#
# Пишется он при разборе makefile — то есть заведомо до всякой компиляции —
# и только на верхнем уровне: theos вызывает make заново на каждый срез,
# и без этой проверки штамп менялся бы посреди сборки.
YC_BUILD_EPOCH ?= $(shell date +%s)

ifeq ($(MAKELEVEL),0)
_YC_STAMP := $(shell echo "#define YC_BUILD_EPOCH $(YC_BUILD_EPOCH)" > src/model/YCBuildStamp.h)
endif

include $(THEOS_MAKE_PATH)/application.mk

##############################################################################
# Права на файлы
##############################################################################
#
# WSL выдаёт всему на диске Windows права 777, и chmod там ничего не меняет.
# Каталог сборки поэтому уносится в файловую систему Linux — но права
# приезжают туда вместе с файлами, и в пакет уходило бы дерево, где и связка,
# и исполняемый файл открыты на запись всему миру. На iOS 6 это сходит с рук,
# дальше — нет: связку с правами 777 LaunchServices не регистрирует,
# а исполняемый файл с такими правами не запускают. Отказ тихий.
after-stage::
	@find $(THEOS_STAGING_DIR) -type d -exec chmod 755 {} +
	@find $(THEOS_STAGING_DIR) -type f -exec chmod 644 {} +
	@chmod 755 $(THEOS_STAGING_DIR)/Applications/$(APPLICATION_NAME).app/$(APPLICATION_NAME)

# То же для служебного каталога пакета, и отдельным шагом: layout/DEBIAN
# переносится сюда позже — уже при упаковке, — так что предыдущее правило
# его ещё не застаёт.
before-package::
	@chmod 755 "$(THEOS_STAGING_DIR)/DEBIAN"
	@for script in preinst postinst prerm postrm; do \
		[ -f "$(THEOS_STAGING_DIR)/DEBIAN/$$script" ] && \
			chmod 755 "$(THEOS_STAGING_DIR)/DEBIAN/$$script"; \
	done; true
	@[ -f "$(THEOS_STAGING_DIR)/DEBIAN/control" ] && \
		chmod 644 "$(THEOS_STAGING_DIR)/DEBIAN/control"; true

##############################################################################
# .ipa
##############################################################################
#
# Имя готового файла: у отладочной сборки своё, иначе они молча перетирают
# друг друга — а немую сборку (FINALPACKAGE выбрасывает NSLog) поставили бы
# туда, где как раз ждали журнал.
ifeq ($(FINALPACKAGE),1)
IPA_NAME = $(APPLICATION_NAME).ipa
else
IPA_NAME = $(APPLICATION_NAME)-debug.ipa
endif

# Payload/YClients.app в zip — то же дерево, что кладётся в .deb.
ipa:: package
	@rm -rf $(THEOS_STAGING_DIR)-ipa
	@mkdir -p $(THEOS_STAGING_DIR)-ipa/Payload
	@cp -r $(THEOS_STAGING_DIR)/Applications/$(APPLICATION_NAME).app \
	       $(THEOS_STAGING_DIR)-ipa/Payload/
	@cd $(THEOS_STAGING_DIR)-ipa && zip -qry \
	       $(CURDIR)/packages/$(IPA_NAME) Payload
	@echo "packages/$(IPA_NAME)"

# Копия библиотеки снимается по времени правки. Если в cYclients поменялось
# имя файла или он удалён — копия об этом не узнает, и собираться будет
# старое. Тогда это.
vendor-clean::
	@rm -rf vendor
	@echo "vendor/ снесён — следующая сборка возьмёт cYclients заново"
