# RESOURCES/KEYS — SWUpdate signing key

The stock ELEGOO Centauri Carbon uses RSA-SHA256 to sign `sw-description`
inside the `update.swu`.  The printer's `swupdate` daemon verifies the
signature against `/etc/swupdate_public.pem`.

---

## Using a custom signing key

If you have replaced `/etc/swupdate_public.pem` on the printer with your
own public key (jailbreak step — see the
[OpenCentauri project](https://github.com/OpenCentauri/cc-fw-tools)),
place the matching RSA private key here as `swupdate_private.pem`:

```
RESOURCES/KEYS/swupdate_private.pem
```

The build script picks it up automatically when you run:

```bash
./build.sh -v 1.1.46 -p e100_lite -r RESOURCES/
```

Or specify a custom path explicitly:

```bash
./build.sh -v 1.1.46 -p e100_lite -r RESOURCES/ -k /path/to/your/private.pem
```

### Generating a new key pair

```bash
# Generate a 2048-bit RSA private key
openssl genrsa -out RESOURCES/KEYS/swupdate_private.pem 2048

# Derive the corresponding public key (upload to the printer via jailbreak)
openssl rsa -in RESOURCES/KEYS/swupdate_private.pem \
            -out RESOURCES/KEYS/swupdate_public.pem \
            -pubout
```

---

## Building without a signing key

If no key is found the build script will still produce `update.swu` and
`update.bin`, but with a **missing or invalid signature**.  Such an update
will be **rejected by stock firmware** and accepted only on printers that
have been jailbroken to skip signature verification.

---

> **Security:** Never commit `swupdate_private.pem` to the repository.
> Both `*.pem` files in this directory are listed in the top-level
> `.gitignore` to prevent accidental exposure.
