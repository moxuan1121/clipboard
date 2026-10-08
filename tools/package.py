"""Keep the default injection path without owning the framework's directories."""
import io
import pathlib
import sys
import tarfile

package = pathlib.Path(sys.argv[1])
archive = package.read_bytes()
assert archive.startswith(b'!<arch>\n'), 'Not a DEB archive'
result = bytearray(archive[:8])
offset = 8
found = False
shared = {'Library/MobileSubstrate', 'Library/MobileSubstrate/DynamicLibraries'}
while offset < len(archive):
    header = archive[offset:offset + 60]
    assert len(header) == 60 and header[58:] == b'`\n', 'Invalid ar header'
    size = int(header[48:58])
    payload = archive[offset + 60:offset + 60 + size]
    assert len(payload) == size, 'Truncated archive'
    if header[:16].decode().strip().rstrip('/') == 'data.tar.xz':
        found = True
        output = io.BytesIO()
        with tarfile.open(fileobj=io.BytesIO(payload), mode='r:xz') as source:
            with tarfile.open(fileobj=output, mode='w:xz') as target:
                for member in source:
                    name = member.name.removeprefix('./').rstrip('/')
                    if member.isdir() and name in shared:
                        continue
                    target.addfile(member, source.extractfile(member) if member.isfile() else None)
        payload = output.getvalue()
        header = header[:48] + f'{len(payload):<10}'.encode() + header[58:]
    result.extend(header)
    result.extend(payload)
    if len(payload) % 2:
        result.extend(b'\n')
    offset += 60 + size + size % 2
assert found, 'Expected xz-compressed data member'
package.write_bytes(result)
