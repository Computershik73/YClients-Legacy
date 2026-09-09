# -*- coding: utf-8 -*-
"""Проверка готовой сборки: что должно быть внутри, а чего быть не должно.

Запускается после `make package ipa FINALPACKAGE=1`:

    python3 tools/check-release.py .theos/obj/YClients.app/YClients

Возвращает 1 при расхождении — годится для CI. Ищет и в UTF-8, и в UTF-16:
литералы с кириллицей clang кладёт в __TEXT,__ustring, и обычный `strings`
их не показывает вовсе.
"""
import sys

path = sys.argv[1] if len(sys.argv) > 1 else '.theos/obj/YClients.app/YClients'
data = open(path, 'rb').read()

print('файл: %s (%d Б)' % (path, len(data)))

def present(needle):
    # Литералы с кириллицей clang кладёт в UTF-16 (__TEXT,__ustring),
    # чисто латинские остаются в UTF-8 (__cstring). Ищем обе.
    return (needle.encode('utf-8') in data) or (needle.encode('utf-16-le') in data)

def check(needle, label, expected):
    got = present(needle)
    mark = 'ок  ' if got == expected else 'ПЛОХО'
    print('  %s %-7s %s' % (mark, 'есть' if got else 'нет', label))
    return got == expected

ok = True
print('--- поверка самого метода ---')
ok &= check('Войти', 'кнопка «Войти»', True)
ok &= check('О программе', 'заголовок «О программе»', True)

print('--- тайм-бомба: обязана быть ---')
ok &= check('Срок этой сборки истёк', 'текст об истечении', True)
ok &= check('работает до', 'строка со сроком', True)
ok &= check('clock.serverTime', 'ключ времени сервера', True)
ok &= check('EEE, dd MMM yyyy HH:mm:ss zzz', 'разбор заголовка Date', True)

print('--- прокси: не должно быть ---')
ok &= check('Прокси для отладки', 'строка на экране входа', False)
ok &= check('Прокси', 'слово «Прокси»', False)
ok &= check('Через прокси', 'запись в журнал о прокси', False)

print('--- журнал: не должно быть ---')
ok &= check('yclients.log', 'имя файла журнала', False)
ok &= check('[YClients/HTTP]', 'записи HTTP', False)

print('\n%s' % ('Всё в порядке.' if ok else 'ЕСТЬ РАСХОЖДЕНИЯ.'))
sys.exit(0 if ok else 1)
