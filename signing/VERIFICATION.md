# Verifying Devolutions Server image signatures (Notation)

> Applies once `devolutions/devolutions-server` images are signed with Notation. Until that migration lands, images are cosign-signed — see the "Image Signature Verification" section of [chart/README.md](../chart/README.md).

Devolutions Server container images are signed with the [Notary Project](https://notaryproject.dev/) (`notation`) using the Devolutions GlobalSign EV code-signing certificate. Signatures are stored as native OCI 1.1 referrers and are RFC 3161 timestamped, so they stay verifiable after the signing certificate expires.

Trust material in this directory:

- `devolutions-codesign.pem` — the Devolutions code-signing certificate(s) (public). Trust these to pin verification to Devolutions.
- `globalsign-tsa-root-r6.pem` — GlobalSign Root CA - R6, used to verify the signature timestamp.

## Manual verification with `notation`

```bash
# 1. Trust the Devolutions signing cert and the timestamp root
notation cert add --type ca --store devolutions signing/devolutions-codesign.pem
notation cert add --type tsa --store devolutions-tsa signing/globalsign-tsa-root-r6.pem

# 2. Trust policy: only accept Devolutions-signed, timestamped devolutions-server images
cat > ~/.config/notation/trustpolicy.json <<'EOF'
{
  "version": "1.0",
  "trustPolicies": [
    {
      "name": "devolutions-server",
      "registryScopes": [ "docker.io/devolutions/devolutions-server" ],
      "signatureVerification": { "level": "strict" },
      "trustStores": [ "ca:devolutions", "tsa:devolutions-tsa" ],
      "trustedIdentities": [ "*" ]
    }
  ]
}
EOF

# 3. Verify (pin by digest)
notation verify docker.io/devolutions/devolutions-server@sha256:<digest>
```

`trustedIdentities: ["*"]` accepts any certificate in the `ca:devolutions` store — and that store contains only the Devolutions certs above, so trust is effectively pinned to Devolutions.

## Kyverno policy

If you use [Kyverno](https://kyverno.io/), enforce verification at admission with an `ImageValidatingPolicy` `notary` attestor. The example audits a namespace — change `validationActions` to `["Enforce"]` to block unsigned images.

```yaml
apiVersion: policies.kyverno.io/v1
kind: ImageValidatingPolicy
metadata:
  name: verify-dvls-image-signatures
spec:
  webhookConfiguration:
    timeoutSeconds: 15
  evaluation:
    background:
      enabled: true
  validationActions: ["Audit"]
  matchConstraints:
    resourceRules:
      - apiGroups: [""]
        apiVersions: ["v1"]
        operations: ["CREATE", "UPDATE"]
        resources: ["pods"]
    namespaceSelector:
      matchLabels:
        kubernetes.io/metadata.name: devolutions-server    # adjust to your namespace
  matchImageReferences:
    - glob: "devolutions/devolutions-server:*"
  credentials:
    secrets: ["docker-hub"]    # your Docker Hub pull secret
  attestors:
    - name: notary
      notary:
        certs:
          value: |
            -----BEGIN CERTIFICATE-----
            MIIHsTCCBZmgAwIBAgIMc9PDNgP/i7RCJPJeMA0GCSqGSIb3DQEBCwUAMFwxCzAJBgNVBAYTAkJF
            MRkwFwYDVQQKExBHbG9iYWxTaWduIG52LXNhMTIwMAYDVQQDEylHbG9iYWxTaWduIEdDQyBSNDUg
            RVYgQ29kZVNpZ25pbmcgQ0EgMjAyMDAeFw0yMzEwMzAxNzUxMThaFw0yNjEwMzAxNzUxMThaMIHx
            MR0wGwYDVQQPDBRQcml2YXRlIE9yZ2FuaXphdGlvbjETMBEGA1UEBRMKMTE2MjU0NDY4OTETMBEG
            CysGAQQBgjc8AgEDEwJDQTEXMBUGCysGAQQBgjc8AgECEwZRdWViZWMxCzAJBgNVBAYTAkNBMQ8w
            DQYDVQQIEwZRdWViZWMxEjAQBgNVBAcTCUxhdmFsdHJpZTEYMBYGA1UEChMPRGV2b2x1dGlvbnMg
            SW5jMRgwFgYDVQQDEw9EZXZvbHV0aW9ucyBJbmMxJzAlBgkqhkiG9w0BCQEWGHNlY3VyaXR5QGRl
            dm9sdXRpb25zLm5ldDCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBAJ8OTpzV4Iv2tO+r
            UPWWrUaZTTxkrJhAlDsRv+ZEWlFeqk4WLJKd/wHKxhtnjLgyciXszZaNzmfUlxdH0E9aaQkucjus
            VPCmr87nEpTBbbT8RjI64XtNqxGrqiWWObvd1wuOu3nP9ra7aA768xLwtVjpRcoAZkYiKAyg9L3Z
            /YySQqZ0SYDl2nBsAtR+8f2zLSqSdR9Bjp2yWkjw9uNMLH0ZjnGoJMy0FBxYHmwGf8jRgCWnnK46
            f7aBri9Ry5wBlNWx6hEj8myfkpZZvSIz3Ctu/4M4LNwC0EX5iPYqnzAdFZ8wK6a7hi5hzBNjeFsi
            41GhSLyPicum2MZrPtHdR8Cvhv+sfhWDz+X258/rVntulKRlsiWeHcaPL1QkKPDnCC5C5yeWVJs0
            2DlkF3u/cNFQrAq/MX1Nig4RHAZ15jy5Lh+dJg/te4YX1v5yhn8PmC4Zp5uIkkSh1EmQZ2I/k/7q
            Ms7jd3OCYHiGZZu4XnCh9Fhd3WKEU5/hoEfarMecWQO+nnN5yUyWCgu7ElVviZTfpnzgqcm5Pt89
            OEr1Fs0Sio8/N3UFhwJxGZVosJgfD7oCCZVebduAKy/jMz8OqTJx89fXWwFd51h1Mni2KG0WjV5G
            p9CxcSK835djBQgn8R18dSZodT7t5iGBI9XKc+b0WrWYAALcqof7pG0ikSalAgMBAAGjggHbMIIB
            1zAOBgNVHQ8BAf8EBAMCB4AwgZ8GCCsGAQUFBwEBBIGSMIGPMEwGCCsGAQUFBzAChkBodHRwOi8v
            c2VjdXJlLmdsb2JhbHNpZ24uY29tL2NhY2VydC9nc2djY3I0NWV2Y29kZXNpZ25jYTIwMjAuY3J0
            MD8GCCsGAQUFBzABhjNodHRwOi8vb2NzcC5nbG9iYWxzaWduLmNvbS9nc2djY3I0NWV2Y29kZXNp
            Z25jYTIwMjAwVQYDVR0gBE4wTDBBBgkrBgEEAaAyAQIwNDAyBggrBgEFBQcCARYmaHR0cHM6Ly93
            d3cuZ2xvYmFsc2lnbi5jb20vcmVwb3NpdG9yeS8wBwYFZ4EMAQMwCQYDVR0TBAIwADBHBgNVHR8E
            QDA+MDygOqA4hjZodHRwOi8vY3JsLmdsb2JhbHNpZ24uY29tL2dzZ2NjcjQ1ZXZjb2Rlc2lnbmNh
            MjAyMC5jcmwwIwYDVR0RBBwwGoEYc2VjdXJpdHlAZGV2b2x1dGlvbnMubmV0MBMGA1UdJQQMMAoG
            CCsGAQUFBwMDMB8GA1UdIwQYMBaAFCWd0PxZCYZjxezzsRM7VxwDkjYRMB0GA1UdDgQWBBT5ymf4
            g+pZGcTmsd4j5s7xv9fz2jANBgkqhkiG9w0BAQsFAAOCAgEAGvu6RRlge5FgpvQl2hWH0vCeCfjm
            b8EGD3SNMvkIXpk/jFgHaRoo3frqx8Bu+YpOFuB9wi83bo2NLX9wVdp3lp/qzk7MZSJz6YAVk6Fu
            lfzUZ52wCfGXUPgEomzb6JaH94ra9tr8rcnlXZntLtgWAeoXS+WYO03GcFDyOwjfTOtty5gmjB+3
            xYuN9biGvRJ0AiTYXhfUJMaG0lUy49zHJS6+uaSenWDbL32Nzl5cDqqnQKJRsULVHcLWSllhPizG
            K7zoHeRtjompM7Z/Ty2O+mKHfpR4UIL8HJkHNvUPwUUhoqISuOUMdUwgEJjVesQQMQmkjIxHKhte
            wi6KzKfhOkrwmpFvQLSikPO8TwGUq+qWqYd9p9s5RcUfmDP8X1qIkAx8fKHh11SD2cVwX5gpYqny
            Gl1ohb7mm2WwLYtJLm3O0xRdGKxR//MJN4tDYwBdztWXSxzxkP1Spv3Cb62Yrdka+cMoKKTATxhT
            7L3qiAVTJsZwRZdRiTdC+5cp5LT3+/pA7BuBjejkSSs1DI9S6AjYezJa2YuFN0Mz8+eP47Y0M2Q9
            e8aKyzZvQ7zJQxWSH0LQcbhZLcv8TGgzWR43Vh3ngVoWGTXNC/cpBoLswlTy5muasgks810Q8YqI
            V8jwIshX/TiMAitH4DhINoKkNPP5cNkXuQ/jYobJsmJIPWo=
            -----END CERTIFICATE-----
            -----BEGIN CERTIFICATE-----
            MIIHszCCBZugAwIBAgIMTBZCMes1fh+PwkUoMA0GCSqGSIb3DQEBCwUAMFwxCzAJBgNVBAYTAkJF
            MRkwFwYDVQQKExBHbG9iYWxTaWduIG52LXNhMTIwMAYDVQQDEylHbG9iYWxTaWduIEdDQyBSNDUg
            RVYgQ29kZVNpZ25pbmcgQ0EgMjAyMDAeFw0yNTEyMDQyMTAyMjRaFw0yODEyMDQyMTAyMjRaMIHz
            MR0wGwYDVQQPDBRQcml2YXRlIE9yZ2FuaXphdGlvbjETMBEGA1UEBRMKMTE2MjU0NDY4OTETMBEG
            CysGAQQBgjc8AgEDEwJDQTEXMBUGCysGAQQBgjc8AgECEwZRdWViZWMxCzAJBgNVBAYTAkNBMQ8w
            DQYDVQQIEwZRdWViZWMxEjAQBgNVBAcTCUxhdmFsdHJpZTEZMBcGA1UEChMQREVWT0xVVElPTlMg
            SU5DLjEZMBcGA1UEAxMQREVWT0xVVElPTlMgSU5DLjEnMCUGCSqGSIb3DQEJARYYc2VjdXJpdHlA
            ZGV2b2x1dGlvbnMubmV0MIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAq8ZKamwIPGJX
            h9qmwU8JWE0yl92WCvMWEKJedfQbLtm7Z7twMyXZE2jQfyGko0eFI4OSC5Zg0tl+Yz5um8TYVss3
            ShjFSaUQeIFlY3z7R2rXTJuR9Bmn4773lLeZfd5x0pMGE9gHsjkdg1YE9HUC7zpjrzH4sFpO0zcB
            j/O/AHaAxt59mwoBr0v2enWXtSM3qp9myRAb7NHEKP7zwKDqyuQJjI278sycW1YidtvG6qSHV11N
            MCZVVJQ5def68q1QTaFPD/bnHemxscsuBwturQThnDOZE8Hamz3vZqi4RoyQ+Fhc7gpO1NkWPoah
            jLawBRobGA+AAMR5lj+C6GpIEA2efZZrqNqhyAy+82FIl3tpB+V2+mzRlDJ6tWtrvOCipPQmTIs0
            eb0AqI1X6YlAeqKtfEv5jvS87i4UlW6TK9x4074L7LRF7vulvwGe1F+5I51zJKPW/81Dt4cBXr/N
            jbXGVizAjPu7KygdB5kQxaURfxuMk2MO+RPUFQX2PrnmFV7LGlnO9pKAt2l2llVI5DNKR2IfQo6E
            GJD1Hk+lrb9b2qF0s2L6wqOvX/EQpI53V8UbnpGI3h6az1h0RBH0qucatWlBDRApK62oWJZSVSoK
            Ba4PBM97ZX5S8drbECVmVtgDMZ9fxzo4ieIUuNZzFcpXbVHtU/xR9DGt/fw9qkkCAwEAAaOCAdsw
            ggHXMA4GA1UdDwEB/wQEAwIHgDCBnwYIKwYBBQUHAQEEgZIwgY8wTAYIKwYBBQUHMAKGQGh0dHA6
            Ly9zZWN1cmUuZ2xvYmFsc2lnbi5jb20vY2FjZXJ0L2dzZ2NjcjQ1ZXZjb2Rlc2lnbmNhMjAyMC5j
            cnQwPwYIKwYBBQUHMAGGM2h0dHA6Ly9vY3NwLmdsb2JhbHNpZ24uY29tL2dzZ2NjcjQ1ZXZjb2Rl
            c2lnbmNhMjAyMDBVBgNVHSAETjBMMEEGCSsGAQQBoDIBAjA0MDIGCCsGAQUFBwIBFiZodHRwczov
            L3d3dy5nbG9iYWxzaWduLmNvbS9yZXBvc2l0b3J5LzAHBgVngQwBAzAJBgNVHRMEAjAAMEcGA1Ud
            HwRAMD4wPKA6oDiGNmh0dHA6Ly9jcmwuZ2xvYmFsc2lnbi5jb20vZ3NnY2NyNDVldmNvZGVzaWdu
            Y2EyMDIwLmNybDAjBgNVHREEHDAagRhzZWN1cml0eUBkZXZvbHV0aW9ucy5uZXQwEwYDVR0lBAww
            CgYIKwYBBQUHAwMwHwYDVR0jBBgwFoAUJZ3Q/FkJhmPF7POxEztXHAOSNhEwHQYDVR0OBBYEFBz0
            BXTVeq8fOSR5EOPQV6iQY+fAMA0GCSqGSIb3DQEBCwUAA4ICAQC67LrgjleBhagrOdc4rMExTPg1
            Mae/Vw3yi9f2kmVVR94iGKl98TpZkf3B4dn7c6F5OgHi/wlYShs4F9lvP/wUjbRaJeC0++pThP+O
            7xmdVS/5eJ2VN1NGfoDNePKSnIlotcwkDgEy+XkhLFRViCdJw6k/qECpaw8PKnkJU4uZhbNk0pa9
            8EYyIQjAL6Ez6aSooGcO7VXS1T1ANupeAGrAGnUErFaDlvExgI2QLXlbCo/xVVdGT/fnjHVRrzss
            cY5IcEihufJJFsr6iecYRKop5ULOovkO9NUEZnKNEBFxhTSZjnWtoGcnn9hp3fLtH55Ii5SOHfkk
            1fBgAdiVZdixXN9ofg6AVJpKQlwvSJ4fgxPbFPyQhM5v70oSW9xjIWXFaGAg9b++9jq+pTloyUwJ
            NwhZNkFvOn13AI2wBiGGrg6SfknV7mP5tohPnw2A6GxmOwwTpU7WxiPXNSoomcPNry9WJk7uQpod
            e2DrDYKC9880o761mdxYRfdggRp2m3+3RQWUnmYBa2UjPF/7v0D9rwvslbFzA1xnXNS/L+aP5v/Q
            bVLes8K2yHsFpSywxVwdHO5qfP7MwwFxBx3DHDIzVTl+fIWMExu+wCFEkHpzrybUhsHysz1A2uNl
            fhjphPHPVQ4IyTYO6wj5AdgiWJ3MmXXq1gPcOUXnF5/HJBx0Sw==
            -----END CERTIFICATE-----
        tsaCerts:
          value: |
            -----BEGIN CERTIFICATE-----
            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
            5hpxbqCo8YLoRT5s1gLXCmeDBVrJpBA=
            -----END CERTIFICATE-----
            
  validationConfigurations:
    required: false
    verifyDigest: false
    mutateDigest: false
  validations:
    - expression: >-
        images.containers
        .filter(image, image.matches("(docker\\.io/)?devolutions/devolutions-server:.*"))
        .map(image, verifyImageSignatures(image, [attestors.notary]))
        .all(e, e > 0)
      message: "failed image signature verification"
```
