"""
Python test dependency pre-install script.
"""
import re
import os
import zipfile
import subprocess
import sys
import urllib.request
import requests


def download_zip(zip_url, local_dir):
    """
    Download the zip file from the given URL to a local directory.

    Args:
    - zip_url (str): URL of the zip file to download.
    - local_dir (str): Directory to save the downloaded zip file locally.
    """
    local_file_name = os.path.join(local_dir, os.path.basename(zip_url))
    if not os.path.exists(local_file_name):
        with requests.get(zip_url, verify=False, stream=True) as req:
            req.raise_for_status()
            with open(local_file_name, 'wb') as file:
                for chunk in req.iter_content(chunk_size=8192):
                    file.write(chunk)


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
            zip_url = url
            test_name = path.split('/')[-1] if '/' in path else path
        else:
            # Handle sha URLs
            parts = url.split('#')
            zip_url = parts[0]
            test_name = path.split('/')[-1] if '/' in path else path

        # Check if test is already processed
        if (path, test_name) in unique_tests:
            continue

        unique_tests.add((path, test_name))

        extracted_data.append({
            'zip_url': zip_url,
            'path': path,
            'test_name': test_name,
        })

    return extracted_data


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
    # Process each test and retrieve metadata content
    for test_entry in test_data:
        zip_url = test_entry['zip_url']
        path = test_entry['path']

        # Download the zip file locally
        download_zip(zip_url, local_dir)

        # Extract the zip file
        with zipfile.ZipFile(os.path.join(local_dir, os.path.basename(zip_url)), 'r') as zip_ref:
            if [i for i in zip_ref.namelist() if path in i]:
                # Extract the 'metadata' file from the directory
                metadata_file = os.path.join(path, 'metadata')
                metafile = [i for i in zip_ref.namelist() if metadata_file in i]
                if metafile:
                    with zip_ref.open(metafile[0]) as metadata:
                        dependencies_match = dependencies_pattern.search(
                            metadata.read().decode('utf-8'))
                        soft_dependencies_match = soft_dependencies_pattern.search(
                            metadata.read().decode('utf-8'))
                        if dependencies_match:
                            dependencies_set.update(dependencies_match.group(1).split(';'))
                        if soft_dependencies_match:
                            soft_dependencies_set.update(
                                soft_dependencies_match.group(1).split(';'))
                else:
                    print(f"{path} :: No metadata file found.")
            else:
                print("No directory found for the test.")

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
    try:
        subprocess.run(['dnf', 'list', 'installed', package_name], check=True,
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        return True  # Package is installed
    except subprocess.CalledProcessError:
        return False  # Package is not installed


def check_available(package_name):
    """
    Use dnf to verify if a package is available through a supplied repository.

    Args:
    - package_name (str): single package.
    """
    try:
        subprocess.run(['dnf', 'info', package_name], check=True,
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        return True  # Package is available
    except subprocess.CalledProcessError:
        return False  # Package is not available


def filter_packages(packages):
    """
    filter packages based on installation and availability

    Args:
    - pkgmgr (str): single package.
    - packages (list): List of packages to be installed.
    Returns:
        None
    """
    return [pkg for pkg in packages if not check_installed(pkg) and check_available(pkg)]


def install_packages(pkgmgr, packages):
    """
    Install the specified packages using the found package manager.

    Args:
    - pkgmgr (str): Package manager command with args.
    - packages (list): List of packages to be installed.
    """
    try:
        if packages:
            command = pkgmgr + ' ' + ' '.join(packages)
            subprocess.run(command, check=True, shell=True)
            print("Packages installed successfully.")

    except subprocess.CalledProcessError as err:
        print("Error installing packages:", err)


def main():
    local_dir = '/var/tmp' # working dir
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
