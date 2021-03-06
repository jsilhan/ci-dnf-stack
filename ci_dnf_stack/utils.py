from __future__ import print_function, unicode_literals

from datetime import datetime
import os
import re
import shutil
import string
import subprocess
import sys
import tarfile
import tempfile

import pygit2

def _fixup_spec(package, spec):
    """
    :param package: Package name
    :type package: str
    :param spec: RPM Spec
    :type spec: str
    :return: RPM Spec
    :rtype: str
    """
    # FIXME: https://github.com/libgit2/pygit2/issues/616
    # pygit2.write_archive() looses permissions on files
    # some of packages requires them, e.g. libsolv
    tmp = spec.split("\n")
    if package == "libsolv":
        tmp.insert(tmp.index("%check") + 1, "chmod +x test/runtestcases")
    elif package == "librepo":
        tmp.insert(tmp.index("%prep") + 2, "find tests/ -type f -name '*.sh.in' -exec chmod +x {} ';'")
    return "\n".join(tmp)

def _get_version(package, repository, commit=None):
    """
    :param repository: Repository
    :type repository: pygit2.Repository
    :param commit: Commit
    :type commit: pygit2.Commit | None
    :param prefix: Prefix
    :type prefix: str | None
    :return: Version and release
    :rtype: tuple(str, str)
    """
    ver = repository.describe(commit, describe_strategy=pygit2.GIT_DESCRIBE_TAGS)
    if ver.startswith("{}-".format(package)):
        ver = ver[len(package) + 1:]
    index = ver.find("-")
    if index > 0:
        version = ver[:index]
        release = ver[index + 1:].replace("-", "")
    else:
        version = ver
        release = "1"

    return version, release

def _templatify_spec(rpmspec):
    """
    :param rpmspec: Path to RPM Spec file
    :type rpmspec: str
    :return: Template
    :rtype: string.Template
    """
    with open(rpmspec, "r") as specfile:
        spec = specfile.readlines()

    # Wipe out changelog
    chlog_index = spec.index("%changelog\n")
    spec = spec[:chlog_index + 1]

    out = []
    # Templatify version/release/etc.
    patch_re = re.compile(r"^Patch\d+:")
    for line in spec:
        line = line.replace("$", "$$")
        line = line.rstrip()
        if line.startswith("Version:"):
            line = "Version: ${version}"
        elif line.startswith("Release:"):
            line = "Release: ${release}%{?dist}"
        elif patch_re.match(line) or line.startswith(("%patch", "%autopatch")):
            # Wipe out all patches
            continue
        elif line.startswith("Source0:"):
            line = "Source0: ${archive}"
        elif line.startswith(("%setup", "%autosetup")):
            line = "%autosetup -n ${directory}"
        out.append(line)

    out.append("${changelog}")

    return string.Template("\n".join(out))

def _gen_changelog(version, release):
    """
    :param version: Version
    :type version: str
    :param release: Release
    :type release: str
    :return: Changelog entry
    :rtype: str
    """
    out = []
    out.append("* {} - {}-{}".format(datetime.now().strftime("%a %b %d %Y"),
                                     version, release))
    out.append("- Autogenerated")
    return "\n".join(out)

def build_srpm(package, repository, rpmspec, commit_sha=None):
    """
    Builds SRPM from upstream repository and RPM spec file.

    :param repository: Upstream repository
    :type repository: str | pygit2.Repository
    :param spec: Path to RPM Spec file
    :type spec: str
    :param commit_sha: Commit hash
    :type commit_sha: str | None
    :return: SRPM path
    :rtype: str
    """
    if isinstance(repository, pygit2.Repository):
        repo = repository
    else:
        repo = pygit2.Repository(pygit2.discover_repository(repository))

    if commit_sha is None:
        commit = repo.head
        oid = commit.target
    else:
        commit = repo[commit]
        oid = commit.oid

    version, release = _get_version(package, repo, commit=commit)
    prefix = "{}-{}-{}".format(package, version, release)

    # Prepare archive
    archive_prefix = "{}/".format(prefix)
    if sys.version_info.major >= 3:
        archive_ext = "tar.xz"
        archive_mode = "w:xz"
    else:
        archive_ext = "tar.gz"
        archive_mode = "w:gz"
    archive_name = "{}.{}".format(prefix, archive_ext)

    spec_tmpl = _templatify_spec(rpmspec)
    spec = spec_tmpl.substitute(version=version,
                                release=release,
                                archive=archive_name,
                                directory=archive_prefix,
                                changelog=_gen_changelog(version, release))
    spec = "\n".join((line.replace("$$", "$") for line in spec.split("\n")))

    spec = _fixup_spec(package, spec)

    # TODO: Use tempfile.TemporaryDirectory() contextmanager once we will migrate to py3
    tmpdir = tempfile.mkdtemp(prefix=prefix)
    try:
        with tarfile.open(os.path.join(tmpdir, archive_name), archive_mode) as archive:
            repo.write_archive(repo[oid], archive, prefix=archive_prefix)
        with open("{}.spec".format(package), "w") as specfile:
            specfile.write(spec)
            specfile.flush()
        out = subprocess.check_output(["rpmbuild", "-bs", specfile.name,
                                       "--define", "_sourcedir {}".format(tmpdir)])
    finally:
        shutil.rmtree(tmpdir)

    return re.match("^Wrote: (.+)$", out.decode("utf-8")).group(1)
