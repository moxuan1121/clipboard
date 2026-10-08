"""Exercise real dpkg path migration with and without the compatibility symlink."""
import pathlib, subprocess, sys, tempfile

old, new = map(lambda value: str(pathlib.Path(value).resolve()), sys.argv[1:])
for alias in (False, True):
    with tempfile.TemporaryDirectory(prefix='clipboard-dpkg-') as directory:
        root = pathlib.Path(directory)
        (root / 'var/lib/dpkg').mkdir(parents=True)
        (root / 'var/lib/dpkg/status').touch()
        target = root / 'usr/lib/TweakInject'
        target.mkdir(parents=True)
        sentinel = target / 'other-package.dylib'
        sentinel.write_bytes(b'keep untouched')
        link = root / 'Library/MobileSubstrate/DynamicLibraries'
        link.parent.mkdir(parents=True)
        if alias:
            link.symlink_to('../../usr/lib/TweakInject', target_is_directory=True)
        for package in (old, new):
            subprocess.run(['dpkg', '--root', directory, '--force-architecture', '--force-depends', '--install', package], check=True)
        assert (link / 'Clipboard.dylib').is_file(), f'New dylib missing; symlink={alias}'
        assert (link / 'Clipboard.plist').is_file()
        assert sentinel.read_bytes() == b'keep untouched'
        subprocess.run(['dpkg', '--root', directory, '--remove', 'com.moxuan1121.clipboard'], check=True)
        assert not (link / 'Clipboard.dylib').exists()
        assert sentinel.read_bytes() == b'keep untouched'
        if alias:
            assert link.is_symlink(), 'Shared compatibility symlink removed'
print('Real dpkg upgrade/removal passed for separate and aliased injection paths.')
