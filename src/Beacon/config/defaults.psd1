# Every value Beacon uses, in one place. A value that differs between machines also has an environment variable.
@{
    TimeoutSeconds      = @{
        Dns  = 5
        Port = 5
        Tls  = 10
        Http = 15
    }
    Route               = @{
        MaxHops           = 15
        HopTimeoutSeconds = 2
        PingBufferBytes   = 32
    }
    # Beacon tests the declared ports, it does not scan: a longer range is an input error.
    MaxPortsPerTarget   = 32
    Http                = @{
        # Status classes when a check declares no expected outcome; a timeout is always a failure.
        OkClasses    = @(2, 3)
        WarnClasses  = @(4, 5)
        # Characters of the body shown in the detail when the answer is not OK.
        PreviewChars = 300
    }
    # Console table: total width and the widest subject; longer details wrap, never cut.
    Report              = @{
        Width        = 120
        SubjectChars = 40
    }
    # Run folders go here, relative to the working directory; BEACON_RUNS overrides it.
    RunsFolder          = 'beacon-runs'
    RunsFolderEnv       = 'BEACON_RUNS'
    ResultSchemaVersion = 1
}
