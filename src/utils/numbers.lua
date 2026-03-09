-- limpa formatação de números (ex: 133,260 -> 133260)
local function normalizeNumber(text)

    if not text then
        return "0"
    end

    text = tostring(text)

    -- remove vírgulas, pontos e espaços
    text = text:gsub("[,%s]", "")
    text = text:gsub("%.", "")

    return text
end

return {
    normalizeNumber = normalizeNumber,
}