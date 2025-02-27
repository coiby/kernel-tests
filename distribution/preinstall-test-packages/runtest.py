import re
import os
import tarfile
import zipfile
import subprocess
import sys
import urllib.request
import requests


def download_archive(archive_url, local_dir):
    """
    Download the zip file from the given URL to a local directory.

    Args:
    - archive_url (str): URL of the  file to download.
    - local_dir (str): Directory to save the downloaded zip file locally.
    """
    local_file_name = os.path.join(local_dir, os.path.basename(archive_url))
    if not os.path.exists(local_file_name):
        with requests.get(archive_url, verify=False, stream=True) as req:
            req.raise_for_status()
            with open(local_file_name, 'wb') as file:
                for chunk in req.iter_content(chunk_size=8192):
                    file.write(chunk)
    print(f"Downloaded archive to {local_file_name}")


def find_tests(xml_data):
    """
    Process the XML data and find the tests.

    Args:
    - xml_data (str): XML data containing information about the tests.

    Returns:
    - List of dictionaries, each containing information about a test.
    """
    pattern = r'<fetch url="(.*?)#(.*?)"'
    matches = re.findall(pattern, xml_data)
    unique_tests = set()
    extracted_data = []

    for match in matches:
        url = match[0]
        path = match[1]

        # Extract zip URL and test name from the URL
        if url.endswith('.zip'):
            archive_url = url
            test_name = path.split('/')[-1] if '/' in path else path
        else:
            # Handle sha URLs
            parts = url.split('#')
            archive_url = parts[0]
            test_name = path.split('/')[-1] if '/' in path else path

        # Check if test is already processed
        if (path, test_name) in unique_tests:
            continue

        unique_tests.add((path, test_name))

        extracted_data.append({
            'archive_url': archive_url,
            'path': path,
            'test_name': test_name,
        })

    print(f"Found {len(extracted_data)} tests")
    return extracted_data


def extract_metadata(archive_ref, path, is_zip, dependencies_pattern, soft_dependencies_pattern, dependencies_set, soft_dependencies_set):
    """
    Extract metadata from an archive and update dependency sets.

    Args:
    - archive_ref: Reference to the opened archive file (zipfile.ZipFile or tarfile.TarFile).
    - path (str): Path within the archive to look for the metadata file.
    - is_zip (bool): True if the archive is a ZIP file, False if it is a TAR file.
    - dependencies_pattern (re.Pattern): Compiled regex pattern to find dependencies in the metadata content.
    - soft_dependencies_pattern (re.Pattern): Compiled regex pattern to find soft dependencies in the metadata content.
    - dependencies_set (set): Set to update with found dependencies.
    - soft_dependencies_set (set): Set to update with found soft dependencies.
    """
    if is_zip:
        namelist = archive_ref.namelist()
    else:
        namelist = archive_ref.getnames()

    if [i for i in namelist if path in i]:
        metadata_file = os.path.join(path, 'metadata')
        metafile = [i for i in namelist if metadata_file in i]
        if metafile:
            if is_zip:
                with archive_ref.open(metafile[0]) as metadata:
                    metadata_content = metadata.read().decode('utf-8')
            else:
                metadata = archive_ref.extractfile(metafile[0])
                if metadata:
                    metadata_content = metadata.read().decode('utf-8')
            dependencies_match = dependencies_pattern.search(metadata_content)
            soft_dependencies_match = soft_dependencies_pattern.search(metadata_content)
            if dependencies_match:
                dependencies_set.update(dependencies_match.group(1).split(';'))
            if soft_dependencies_match:
                soft_dependencies_set.update(soft_dependencies_match.group(1).split(';'))
        else:
            print(f"{path} :: No metadata file found.")
    else:
        print("No directory found for the test.")


def retrieve_metadata(test_data, local_dir):
    """
    Retrieve the zip file, extract it, and read the metadata file for each test.

    Args:
    - test_data (list): List of dictionaries containing information about the tests.
    - local_dir (str): Directory to save the downloaded zip files and extract them.

    Returns:
    - 2 lists of strings for dependencies and soft-dependencies.
    """
    dependencies_set = set()
    soft_dependencies_set = set()
    dependencies_pattern = re.compile(r'dependencies=([\w;-]+)')
    soft_dependencies_pattern = re.compile(r'softDependencies=([\w;-]+)')
    for test_entry in test_data:
        archive_url = test_entry['archive_url']
        path = test_entry['path']
        archive_path = os.path.join(local_dir, os.path.basename(archive_url))
        download_archive(archive_url, local_dir)

        if archive_url.endswith('.zip'):
            with zipfile.ZipFile(archive_path, 'r') as archive_ref:
                extract_metadata(archive_ref, path, True, dependencies_pattern, soft_dependencies_pattern,
                                 dependencies_set, soft_dependencies_set)
        elif archive_url.endswith(('.tar', '.tar.gz', '.tar.bz2')):
            with tarfile.open(archive_path, 'r:*') as archive_ref:
                extract_metadata(archive_ref, path, False, dependencies_pattern, soft_dependencies_pattern,
                                 dependencies_set, soft_dependencies_set)
        else:
            print(f"Unsupported archive format: {archive_url[archive_url.find('com'):]}")

    soft_dependencies_set.difference_update(dependencies_set)
    print(f"Dependencies: {dependencies_set}")
    print(f"Soft dependencies: {soft_dependencies_set}")
    return list(dependencies_set), list(soft_dependencies_set)


def get_pkg_mgr():
    """
    Check for OS package manager.

    Returns:
    - pkgmgr (string): string containing the respective package manager and related args.
    """
    if os.path.exists("/run/ostree-booted"):
        return "rpm-ostree --assumeyes --apply-live --idempotent --allow-inactive install"
    elif os.path.exists("/usr/bin/dnf"):
        return "dnf -y --skip-broken install"
    elif os.path.exists("/usr/bin/yum"):
        return "yum -y --skip-broken install"
    else:
        print("No tool to install")
        sys.exit(1)


def check_installed(package_name):
    """
    Use dnf to validate if a package is already installed.

    Args:
    - package_name (str): single package
    Returns:
    - True or False
    """
    print(f"Checking if package {package_name} is installed")
    try:
        subprocess.run(['dnf', 'list', 'installed', package_name], check=True,
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        return True
    except subprocess.CalledProcessError:
        return False

def check_available(package_name):
    """
    Use dnf to verify if a package is available through a supplied repository.

    Args:
    - package_name (str): single package.
    """
    print(f"Checking if package {package_name} is available")
    try:
        subprocess.run(['dnf', 'info', package_name], check=True,
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        return True
    except subprocess.CalledProcessError:
        return False

def filter_packages(packages):
    """
    filter packages based on installation and availability

    Args:
    - pkgmgr (str): single package.
    - packages (list): List of packages to be installed.
    Returns:
        None
    """
    print("Filtering packages based on installation and availability")
    return [pkg for pkg in packages if not check_installed(pkg) and check_available(pkg)]

def install_packages(pkgmgr, packages):
    """
    Install the specified packages using the found package manager.

    Args:
    - pkgmgr (str): Package manager command with args.
    - packages (list): List of packages to be installed.
    """
    print(f"Installing packages: {packages}")
    try:
        if packages:
            command = pkgmgr + ' ' + ' '.join(packages)
            subprocess.run(command, check=True, shell=True)
            print("Packages installed successfully.")

    except subprocess.CalledProcessError as err:
        print(f"Error installing packages: {err}")


def main():
    local_dir = '/var/tmp'
    xml_file_url = os.environ.get('BEAKERXML_URL')
    with urllib.request.urlopen(xml_file_url) as response:
        xml_data = response.read().decode('utf-8')
    test_data = find_tests(xml_data)
    dependencies, soft_dependencies = retrieve_metadata(test_data, local_dir)
    pkgmgr = get_pkg_mgr()
    req_packages = filter_packages(dependencies)
    opt_packages = filter_packages(soft_dependencies)
    install_packages(pkgmgr, req_packages)
    install_packages(pkgmgr, opt_packages)


if __name__ == "__main__":
    main()
