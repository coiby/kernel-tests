#!/usr/bin/env python3
import argparse
import sys
import os

SYZLANG_START_TAG = "### GENERATED_ARRAY_START ###"
SYZLANG_END_TAG = "### GENERATED_ARRAY_END ###"
SYZKALLER_COMMIT_HASH = "5d7e17caf7d0971d22446d8a81bcf1cd8c18a0dc"

entries = []
syzlang_defs = "\nresource fd_pseudofs[fd]\n\n"

# Add generated new_code to source file in source_file_path,
# delimited by start_tag and end_tag
def update_source_file(source_file_path, new_code, start_tag, end_tag):
    with open(source_file_path, 'r') as f:
        content = f.read()

    # Find the start and end tags for the array
    start_index = content.find(start_tag)
    if start_index == -1:
        raise ValueError(f"start_tag {start_tag} not found!")
    start_index += len(start_tag)
    end_index = content.find(end_tag)
    if end_index == -1:
        raise ValueError(f"end_tag {end_tag} not found!")

    # Replace the content between the tags
    updated_content = content[:start_index] + new_code + content[end_index:]

    with open(source_file_path, 'w') as f:
        f.write(updated_content)

def create_identifier(path: str) -> str:
    """
    Converts a file path into a valid syzlang identifier.
    Example: /proc/sys/vm/panic-on-oom -> proc_sys_vm_panic_on_oom
    """
    if not path:
        return ""
    # Remove leading slash and replace other slashes and hyphens with underscores
    return path.lstrip('/').replace('.', '_').replace('/', '_').replace('-', '_')

def generate_definitions(path: str, args: argparse.Namespace):
    """
    Generates and prints the syzlang definitions for a given procfs path.
    """
    path = path.strip()
    if not path:
        return

    identifier = create_identifier(path)
    if not identifier:
        return

    # --- Template for the syzlang definitions ---

    # openat$IDENTIFIER(fd const[AT_FDCWD], file ptr[in, string["PATH"]], ...)
    openat_def = (
        f'openat${identifier}(fd const[AT_FDCWD], '
        f'file ptr[in, string["{path}"]], flags flags[open_flags], '
        'mode const[0]) fd_pseudofs'
    )

    # read$IDENTIFIER(fd fd_pseudofs, buf buffer[out], ...)
    read_def = f'read${identifier}(fd fd_pseudofs, buf buffer[out], count len[buf])'

    # write$IDENTIFIER(fd fd_pseudofs, buf buffer[in], ...)
    write_def = f'write${identifier}(fd fd_pseudofs, buf buffer[in], count len[buf])'

    global syzlang_defs
    syzlang_defs += openat_def + "\n" + read_def + "\n" + write_def + "\n\n"
    entries.append(f'openat${identifier}')
    entries.append(f'read${identifier}')
    entries.append(f'write${identifier}')


def update_fmf_files(entries: list[str], fmf_groups: int):
    if len(entries) > 0 and fmf_groups > 0:
        # Ensure chunk_size is divisible by 3 for openat/read/write grouping
        # minimal chunk size to fit entries/group_count, rounded up to nearest multiple of 3
        chunk_size = (len(entries) + fmf_groups - 1) // fmf_groups
        if chunk_size % 3 != 0:
            chunk_size += (3 - chunk_size % 3)
        entry_groups = [entries[i*chunk_size:(i+1)*chunk_size] for i in range(fmf_groups)]
    else:
        entry_groups = [[] for _ in range(fmf_groups)]

    group_nr = 1    
    for group in entry_groups:
        list_str = "\n  main_syscalls: |\n"
        for entry in group:
            list_str += f'    "{entry}",\n'
        # Remove the last comma before adding the group to the file, if any entries were added
        if list_str.endswith(",\n"):
            list_str = list_str.rstrip(",\n") + "\n"
        fmf_file = f"group{group_nr}/main.fmf"
        update_source_file(fmf_file, list_str, SYZLANG_START_TAG, SYZLANG_END_TAG)
        group_nr += 1


def generate_syzkaller_patch(syzkaller_path: str, patch_file_path: str):
    os.system(f"cd {syzkaller_path}; git checkout -f {SYZKALLER_COMMIT_HASH}")    
    with open(f"{syzkaller_path}/sys/linux/sys.txt", "a") as f:
        f.write(syzlang_defs)
    os.system(f"cd {syzkaller_path}; git diff > {patch_file_path}")

def main():
    """
    Main function to parse arguments and process the input file.
    """
    parser = argparse.ArgumentParser(
        description="Generate syzlang definitions for pseudofs entries from a file."
    )
    parser.add_argument(
        "input_file",
        help="Path to a file containing a list of pseudofs paths, one per line."
    )
    parser.add_argument(
        "-g", "--fmf-groups",
        type=int,
        default=6,
        help="Update the fmf files with the generated syzlang definitions.",
        required=True
    )
    parser.add_argument(
        "-s", "--syzkaller-path",
        help="Path to the syzkaller repository.",
        required=True
    )
    parser.add_argument(
        "-p", "--patch-file-path",
        help="Path to the output patch file.",
        required=True
    )
    args = parser.parse_args()

    try:
        with open(args.input_file, 'r') as f:
            for line in f:
                generate_definitions(line, args)
        generate_syzkaller_patch(args.syzkaller_path, args.patch_file_path)
        update_fmf_files(entries, args.fmf_groups)
    except FileNotFoundError:
        print(f"Error: Input file not found at '{args.input_file}'", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    main()
