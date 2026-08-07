# Simulator authentication backup

The DEBUG MissCat app can seal its current MiAuth account metadata and access
token for disaster recovery without exposing either value to the host shell.
The bridge is excluded from Release builds.

Run the helper against an already installed, booted simulator:

```sh
scripts/misscat-auth-backup.sh export <simulator-udid>
scripts/misscat-auth-backup.sh restore <simulator-udid>
```

`export` writes an AES-GCM sealed payload to
`~/Desktop/MissCatAuthBackup.enc` and a 256-bit key to
`~/.config/misscat/auth-backup.key`. Both are created atomically with mode
`600`. Keep both files; neither file is useful by itself. The login password is
never read or stored.

Before every operation, the helper removes any stale simulator-side key, input,
or encrypted output file and verifies that all three paths are absent. After a
successful `export`, `restore`, or `clear`, it again removes and verifies all
three staging paths before printing success. A removal or absence-check failure
causes the command to fail closed without reporting success; the exit trap is a
final fallback rather than the primary cleanup mechanism.

The optional `clear` command exists only for a controlled restore test. Run it
only after `export` succeeds and the helper reports a non-empty SHA-256:

```sh
scripts/misscat-auth-backup.sh clear <simulator-udid>
scripts/misscat-auth-backup.sh restore <simulator-udid>
```

Restore decrypts only inside the app process, writes the credential through
MissCat's rollback-safe shared-Keychain transaction, verifies the readback, and
removes the simulator-side key, input, and output staging files. Helper output
contains only operation status, file permissions, and the encrypted backup
checksum.
