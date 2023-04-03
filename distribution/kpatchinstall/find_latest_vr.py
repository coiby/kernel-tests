#!/usr/bin/python

import sys
import os
import re


def parse_vr(somestring):
    somestring = somestring.strip()
    pattern = re.compile('^(.+)-(.+)$')
    match = pattern.search(somestring)
    if match:
        return match.group(1), match.group(2)
    else:
        return None

def compare_lists(list1, list2):
    i = 0
    while i < len(list1) and i < len(list2):
        part1 = list1[i]
        part2 = list2[i]

        if part1.isdigit():
            if part2.isdigit():
                part1 = int(part1)
                part2 = int(part2)
            else:
                return 1
        else:
            if part2.isdigit():
                return -1

        if part1 < part2:
            return -1
        elif part1 > part2:
            return 1
        i = i + 1

    if len(list1) > len(list2):
        return 1
    elif len(list1) < len(list2):
        return -1
    else:
        return 0

def compare_nvr(nvr1str, nvr2str):
    nvr1 = parse_vr(nvr1str)
    nvr2 = parse_vr(nvr2str)

    if nvr1 and nvr2:
        pass
    else:
        return None

    ver1, rel1 = nvr1
    ver2, rel2 = nvr2

    ver1 = ver1.split('.')
    ver2 = ver2.split('.')

    rel1 = rel1.split('.')
    rel2 = rel2.split('.')

    list1 = ver1 + rel1
    list2 = ver2 + rel2

    return compare_lists(list1, list2)


lines = sys.stdin.readlines()
latest = ''

for line in lines:
    line = line.strip()
    line = os.path.dirname(line)
    line = os.path.basename(line)

    if not latest:
        latest = line
    else:
        try:
            if compare_nvr(line, latest) > 0:
                latest = line
        except Exception as e:
            sys.stderr.write('%s\n' % str(e))

print(latest)
