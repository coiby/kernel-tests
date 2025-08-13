import sys
import os
import re # import regex module

def main():
    if len(sys.argv) != 3:
        print("Error: Arguments number not expected")
        return

    folder_path = sys.argv[1]
    syscall = sys.argv[2]

    regex_pattern = re.compile(r"^" + re.escape(syscall) + r"(\$|\()")

    if not os.path.exists(folder_path):
        print(f"Error: Directory '{folder_path}' doesn't exist.", file=sys.stderr)
        print("false")
        return
    if not os.path.isdir(folder_path):
        print(f"Error: '{folder_path}' is not a valid directory", file=sys.stderr)
        print("false")
        return

    found = False

    for filename in os.listdir(folder_path):
        filepath = os.path.join(folder_path, filename)

        if os.path.isfile(filepath):
            try:
                with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
                    for line in f:
                        if regex_pattern.search(line):
                            found = True
                            break
                if found:
                    break
            except Exception as e:
                print(f"Error: Cannot read file '{filepath}' - {e}", file=sys.stderr)

    if found:
        print("executed")
    else:
        print("not executed")

if __name__ == "__main__":
    main()
