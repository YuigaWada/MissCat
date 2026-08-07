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

The optional `clear` command exists only for a controlled restore test. Run it
only after `export` succeeds and the helper reports a non-empty SHA-256:

```sh
scripts/misscat-auth-backup.sh clear <simulator-udid>
scripts/misscat-auth-backup.sh restore <simulator-udid>
```

Restore decrypts only inside the app process, writes the credential through
MissCat's rollback-safe shared-Keychain transaction, verifies the readback, and
removes the simulator-side key and input staging files. Helper output contains
only operation status, file permissions, and the encrypted backup checksum.
