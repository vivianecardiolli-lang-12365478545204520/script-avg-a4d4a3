local config = {}

config.rewards = {
    NewPlayerRewards = 7,
    PirateRewards = 7,
    SpecialRewards = 7,
    WinterRewards = 7,
}

config.tracker = {
    webhookUrl = "https://script.google.com/macros/s/AKfycbz-AVeJQyHfYi03z1nR9-XZilDK8AbuooodJRLD6BiDY6zntd-GlDHhX3r1ZzDwZI0/exec",
    secretToken = "MEU_TOKEN_SUPER_SECRETO_123",
    intervalMinutes = 5,
    retry = {
        maxRetries = 3,
        retryDelaySeconds = 2,
    },
}

config.logger = {
    exportToClipboard = false,
}

return config