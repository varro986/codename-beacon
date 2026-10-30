# Example target matrix: the contract of feature 001. Synthetic names and documentation addresses only.
@{
    Environments = @{
        test = @{
            # Optional: HTTP checks go through this proxy.
            Proxy  = 'http://proxy.example.net:8080'
            Groups = @{
                web = @{
                    Targets = @(
                        @{
                            Name              = 'portal'
                            Host              = 'portal.example.com'
                            ExpectedAddresses = @('192.0.2.10')
                            Ports             = @(443)
                            Urls              = @('https://portal.example.com/health')
                        }
                        @{
                            Name      = 'api'
                            Host      = 'api.example.com'
                            # A port, or an inclusive range as 'from-to'.
                            Ports     = @(443, '8443-8444')
                            Urls      = @('https://api.example.com/v1/items')
                            # Without a token, 401 means the route is open.
                            Expect    = @{ Http = 401 }
                            # Name of the environment variable holding the secret, never the value.
                            SecretEnv = 'BEACON_API_TOKEN'
                        }
                    )
                }
                legacy = @{
                    Targets = @(
                        @{
                            Name  = 'archive'
                            Host  = 'archive.example.org'
                            Ports = @(80)
                        }
                    )
                }
            }
        }
        production = @{
            Groups = @{
                web = @{
                    Targets = @(
                        @{
                            Name  = 'portal'
                            Host  = 'portal.example.com'
                            Ports = @(443)
                            Urls  = @('https://portal.example.com/health')
                        }
                    )
                }
            }
        }
    }
}
