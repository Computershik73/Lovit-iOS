# -*- coding: utf-8 -*-
"""
Проверяет собранный бинарник: платформу, нижние границы, подпись.

Всё, что здесь проверяется, компоновщик молча делает неправильно, а сборка
при этом идёт без единого предупреждения. Замечается такое уже на устройстве,
и хуже всего, что не на всяком: приложение с платформой macOS запускается
на iOS 6 и не запускается на iOS 8, причём без записи в журнале падений —
процесс не падает, его просто не пускают.

    python3 tools/check-macho.py packages/Scam.ipa
    python3 tools/check-macho.py /путь/к/Scam.app/Scam

Возвращает 1, если хоть одна проверка не прошла — годится для CI.
"""
import os
import struct
import sys
import tempfile
import zipfile

# Команды загрузки, которые нас интересуют. Числа соседние и легко
# переставляются местами — они выписаны из mach-o/loader.h как есть.
LC_VERSION_MIN_MACOSX = 0x24
LC_VERSION_MIN_IPHONEOS = 0x25
LC_CODE_SIGNATURE = 0x1D
LC_BUILD_VERSION = 0x32
LC_SYMTAB = 0x02
LC_LOAD_DYLIB = 0x0C
LC_LOAD_WEAK_DYLIB = 0x80000018

# Тип процессора в заголовке.
CPU_ARM = 12
CPU_ARM64 = 0x0100000C

# Нижняя граница, объявленная в Makefile. Она одна на оба среза: поднять её
# у arm64 отдельно theos не даёт, подробности — в самом Makefile.
EXPECTED_MIN = {"armv7": (6, 0), "arm64": (6, 0)}

# Платформа в LC_BUILD_VERSION (новые цепочки пишут её вместо VERSION_MIN).
PLATFORM_IOS = 2


def version(value):
    return (value >> 16, (value >> 8) & 0xFF, value & 0xFF)


def slice_name(cputype, cpusubtype):
    if cputype == CPU_ARM64:
        return "arm64"
    if cputype == CPU_ARM:
        return {9: "armv7", 11: "armv7s", 6: "armv6"}.get(cpusubtype & 0xFF, "arm?")
    return "cpu:%d" % cputype


# Что внутри подписи.
CSMAGIC_EMBEDDED_SIGNATURE = 0xFADE0CC0
CSMAGIC_CODEDIRECTORY = 0xFADE0C02

CSSLOT_CODEDIRECTORY = 0
CSSLOT_ALTERNATE_CODEDIRECTORIES = 0x1000
CSSLOT_ALTERNATE_CODEDIRECTORY_LIMIT = 0x1005

CS_ADHOC = 0x2

# Имена те же, что в ядре: SHA256 — полная, SHA256_TRUNCATED — обрезанная
# до двадцати байт. Путать их нельзя, у них разные номера.
CS_HASHTYPE_SHA1 = 1
CS_HASHTYPE_SHA256 = 2
CS_HASHTYPE_SHA256_TRUNCATED = 3

HASH_NAMES = {1: "SHA-1", 2: "SHA-256", 3: "SHA-256 обрезанная", 4: "SHA-384", 5: "SHA-512"}

# Имя связки: с ним должно совпадать имя в подписи.
BUNDLE_IDENTIFIER = "ru.computershik.lovit"


def check_signature(data, offset, name, problems):
    """
    Смотрит, поймут ли подпись и старая система, и новая.

    Джейлбрейк iOS 6 снимал проверку целиком, и содержимое подписи никого
    не занимало; iOS 8 её разбирает. Отказ там молчаливый — процесс просто
    не заводят, — поэтому проверять приходится заранее и здесь.

    Описаний кода в подписи два, и это нарочно: ядра разных лет читают её
    по-разному, а понимать должны все.

      iOS 6 (xnu-2050)    берёт первое описание из слота 0 и дальше не смотрит;
      iOS 7–9 (xnu-2782)  обходит все слоты, но разбирает описанием только
                          нулевой — остальным достаётся проверка длины;
      iOS 10+ (xnu-3789)  перебирает слот 0 и диапазон ALTERNATE, считает
                          hash_rank (SHA-1 ниже SHA-256) и берёт лучшее.

    Отсюда и требования: в слоте 0 — SHA-1, среди дополнительных — SHA-256,
    и ни одной сводки дважды: новое ядро отвергает подпись, в которой два
    описания одного и того же вида.
    """
    magic, _, count = struct.unpack_from(">III", data, offset)

    if magic != CSMAGIC_EMBEDDED_SIGNATURE:
        problems.append("%s: подпись не разбирается (magic 0x%x)" % (name, magic))
        return

    found = []

    for i in range(count):
        slot, where = struct.unpack_from(">II", data, offset + 12 + i * 8)
        blob = offset + where
        blob_magic = struct.unpack_from(">I", data, blob)[0]

        if blob_magic != CSMAGIC_CODEDIRECTORY:
            continue

        (_, _, _, flags, _, ident_offset,
         _, _, _, hash_size, hash_type, _, _, _) = struct.unpack_from(">IIIIIIIIIBBBBI", data, blob)

        identifier = data[blob + ident_offset:data.index(b"\0", blob + ident_offset)]
        found.append({
            "slot": slot,
            "flags": flags,
            "hash_type": hash_type,
            "hash_size": hash_size,
            "identifier": identifier.decode("utf-8", "replace"),
        })

    if not found:
        problems.append("%s: в подписи нет ни одного описания кода" % name)
        return

    said = ", ".join("%s%s" % (HASH_NAMES.get(cd["hash_type"], "тип %d" % cd["hash_type"]),
                               "" if cd["slot"] == CSSLOT_CODEDIRECTORY else " (второе)")
                     for cd in found)

    main = found[0]
    print("    подпись: %s, сводки %s, имя %s"
          % ("adhoc" if main["flags"] & CS_ADHOC else "НЕ adhoc", said, main["identifier"]))

    for cd in found:
        if not cd["flags"] & CS_ADHOC:
            problems.append("%s: в подписи снят признак adhoc — система пойдёт искать "
                            "удостоверяющую часть, которой в файле нет. Подписывать "
                            "надо с -Cadhoc" % name)
            break

    for cd in found:
        if cd["identifier"] != BUNDLE_IDENTIFIER:
            problems.append("%s: имя в подписи «%s», а связка называется «%s» — "
                            "подписывать надо с -I%s"
                            % (name, cd["identifier"], BUNDLE_IDENTIFIER, BUNDLE_IDENTIFIER))
            break

    primary = [cd for cd in found if cd["slot"] == CSSLOT_CODEDIRECTORY]

    if len(primary) != 1:
        problems.append("%s: описаний кода в слоте 0 должно быть ровно одно, а их %d"
                        % (name, len(primary)))
    elif primary[0]["hash_type"] != CS_HASHTYPE_SHA1 or primary[0]["hash_size"] != 20:
        problems.append("%s: в слоте 0 сводка не SHA-1 — iOS 6–9 другой не знает. "
                        "Подписывать надо без -Hsha256" % name)

    alternates = [cd for cd in found
                  if CSSLOT_ALTERNATE_CODEDIRECTORIES <= cd["slot"]
                  < CSSLOT_ALTERNATE_CODEDIRECTORY_LIMIT]

    if not any(cd["hash_type"] == CS_HASHTYPE_SHA256 and cd["hash_size"] == 32
               for cd in alternates):
        problems.append("%s: в подписи нет второго описания со сводкой SHA-256 — "
                        "iOS 11 и новее такую подпись не примут. Подписывать надо "
                        "без -H вовсе: ldid тогда кладёт обе" % name)

    kinds = [cd["hash_type"] for cd in found]
    for kind in set(kinds):
        if kinds.count(kind) > 1:
            problems.append("%s: сводка %s встречается в подписи дважды — ядро iOS 10 "
                            "и новее такое отвергает"
                            % (name, HASH_NAMES.get(kind, "тип %d" % kind)))


def check_symbol_homes(data, offset, wide, commands, name, problems):
    """
    Проверяет, у какой библиотеки бинарник просит классы Objective-C.

    Двухуровневое пространство имён означает, что dyld ищет символ ровно
    в той библиотеке, которую записал компоновщик, и, не найдя, снимает
    процесс — до main, без записи в журнале падений. А записывает он ту,
    где символ объявлен в SDK 9.3, хотя на старых системах класс мог жить
    в другом месте. Так уже случалось дважды:

        NSObject             libobjc  вместо CoreFoundation (iOS 5.1)
        NSMutableURLRequest  CFNetwork вместо Foundation    (iOS 7.1)

    Правило простое: классы NS* живут в Foundation. Если такой символ
    просят у кого-то ещё — это ровно та ловушка, и лечится она флагом
    -Wl,-U,<символ> в Makefile.

    Константы (kCF*, всё, что не _OBJC_CLASS_$_/_OBJC_METACLASS_$_) не
    проверяются: они остаются там, где лежали.
    """
    symtab = next((c for c in commands if c[0] == LC_SYMTAB), None)
    if symtab is None:
        return

    _, _, symoff, nsyms, stroff, strsize = struct.unpack_from("<IIIIII", data, symtab[1])

    # Порядковый номер библиотеки в n_desc указывает на LC_LOAD_DYLIB по
    # порядку их следования, считая с единицы.
    dylibs = []
    for command, position in commands:
        if command not in (LC_LOAD_DYLIB, LC_LOAD_WEAK_DYLIB):
            continue
        name_offset = struct.unpack_from("<I", data, position + 8)[0]
        raw = data[position + name_offset:position + struct.unpack_from(
            "<I", data, position + 4)[0]]
        path = raw.split(b"\x00")[0].decode("utf-8", "replace")
        dylibs.append(os.path.basename(path))

    entry_size = 16 if wide else 12

    for index in range(nsyms):
        position = offset + symoff + index * entry_size
        n_strx, n_type, _, n_desc = struct.unpack_from("<IBBH", data, position)

        # Нас интересуют только неопределённые внешние символы.
        if (n_type & 0x0E) != 0x00 or not (n_type & 0x01):
            continue

        end = data.index(b"\x00", offset + stroff + n_strx)
        symbol = data[offset + stroff + n_strx:end].decode("utf-8", "replace")

        if not symbol.startswith(("_OBJC_CLASS_$_NS", "_OBJC_METACLASS_$_NS")):
            continue

        ordinal = (n_desc >> 8) & 0xFF
        if ordinal == 0 or ordinal > len(dylibs):
            continue  # ноль означает «искать везде» — как раз то, что нужно

        library = dylibs[ordinal - 1]
        if library in ("Foundation", "CoreFoundation"):
            continue

        problems.append(
            "%s: класс %s просят у %s, а на старых системах он в Foundation — "
            "dyld снимет процесс до main. Добавьте в Makefile "
            "-Wl,-U,%s" % (name, symbol, library, symbol.replace("$", "\\$$")))


def check_slice(data, offset, problems):
    magic = struct.unpack_from("<I", data, offset)[0]
    wide = magic == 0xFEEDFACF

    cputype, cpusubtype = struct.unpack_from("<ii", data, offset + 4)
    ncmds = struct.unpack_from("<I", data, offset + 16)[0]

    name = slice_name(cputype & 0xFFFFFFFF, cpusubtype)
    print("  срез %s" % name)

    platform = None
    minimum = None
    signed = False

    position = offset + (32 if wide else 28)
    commands = []

    for _ in range(ncmds):
        command, size = struct.unpack_from("<II", data, position)
        commands.append((command, position))

        if command in (LC_VERSION_MIN_IPHONEOS, LC_VERSION_MIN_MACOSX):
            _, _, low, sdk = struct.unpack_from("<IIII", data, position)
            platform = "iOS" if command == LC_VERSION_MIN_IPHONEOS else "macOS"
            minimum = version(low)
            print("    %s, нижняя граница %d.%d, SDK %d.%d"
                  % ((platform,) + minimum[:2] + version(sdk)[:2]))

        if command == LC_BUILD_VERSION:
            _, _, which, low, sdk, _ = struct.unpack_from("<IIIIII", data, position)
            platform = "iOS" if which == PLATFORM_IOS else "платформа %d" % which
            minimum = version(low)
            print("    %s, нижняя граница %d.%d, SDK %d.%d"
                  % ((platform,) + minimum[:2] + version(sdk)[:2]))

        if command == LC_CODE_SIGNATURE:
            signed = True
            _, _, sig_offset, _ = struct.unpack_from("<IIII", data, position)
            check_signature(data, offset + sig_offset, name, problems)

        position += size

    check_symbol_homes(data, offset, wide, commands, name, problems)

    if platform is None:
        problems.append("%s: платформа не объявлена вовсе — нет ни "
                        "LC_VERSION_MIN_*, ни LC_BUILD_VERSION" % name)
    elif platform != "iOS":
        problems.append("%s: платформа %s вместо iOS — смотрите тройку цели "
                        "(-target) в Makefile" % (name, platform))

    expected = EXPECTED_MIN.get(name)

    if expected is not None and minimum is not None and minimum[:2] != expected:
        problems.append("%s: нижняя граница %d.%d, а ожидалась %d.%d"
                        % ((name,) + minimum[:2] + expected))

    if not signed:
        problems.append("%s: нет подписи (LC_CODE_SIGNATURE). На iOS 8 и новее "
                        "такой файл не запустится даже с AppSync — нужен "
                        "хотя бы ldid -S" % name)
        print("    подпись: НЕТ")


def check(path, problems):
    data = open(path, "rb").read()

    if len(data) < 8:
        problems.append("%s: файл пуст" % path)
        return

    magic = struct.unpack_from(">I", data, 0)[0]

    if magic in (0xCAFEBABE, 0xCAFEBABF):
        count = struct.unpack_from(">I", data, 4)[0]
        print("%s: универсальный файл, срезов %d" % (os.path.basename(path), count))

        for i in range(count):
            _, _, offset, _, _ = struct.unpack_from(">iiIII", data, 8 + i * 20)
            check_slice(data, offset, problems)

        names = set()
        for i in range(count):
            cputype, cpusubtype, _, _, _ = struct.unpack_from(">iiIII", data, 8 + i * 20)
            names.add(slice_name(cputype & 0xFFFFFFFF, cpusubtype))

        # armv7 — всё от iPhone 3GS до iPhone 5 и оба iPad mini первого
        # поколения; arm64 — всё, что новее. Без одного из срезов половина
        # заявленных устройств останется без приложения.
        for wanted in ("armv7", "arm64"):
            if wanted not in names:
                problems.append("нет среза %s" % wanted)
    else:
        print("%s: один срез" % os.path.basename(path))
        check_slice(data, 0, problems)


def binary_from_ipa(path):
    with zipfile.ZipFile(path) as archive:
        names = [n for n in archive.namelist()
                 if n.startswith("Payload/") and n.count("/") == 2
                 and n.endswith("/" + n.split("/")[1].replace(".app", ""))]

        if not names:
            print("В %s не нашлось исполняемого файла" % path, file=sys.stderr)
            sys.exit(2)

        target = os.path.join(tempfile.mkdtemp(), os.path.basename(names[0]))

        with open(target, "wb") as out:
            out.write(archive.read(names[0]))

        return target


def main():
    if len(sys.argv) != 2:
        print(__doc__)
        sys.exit(2)

    path = sys.argv[1]

    if path.endswith(".ipa"):
        path = binary_from_ipa(path)

    problems = []
    check(path, problems)

    if not problems:
        print("\nВсё в порядке.")
        return 0

    print("\nНе в порядке:")
    for problem in problems:
        print("  * %s" % problem)

    return 1


if __name__ == "__main__":
    sys.exit(main())
