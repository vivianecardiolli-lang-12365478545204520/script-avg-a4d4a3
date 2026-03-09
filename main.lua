local HttpLoader = {
    baseUrl = "https://raw.githubusercontent.com/vivianecardiolli-lang-12365478545204520/script-avg-a4d4a3/refs/heads/main/src/",
}

local moduleCache = {}

local function normalizeBaseUrl(url)
    if url:sub(-1) ~= "/" then
        return url .. "/"
    end
    return url
end

local function fetchModuleSource(url)
    if request then
        local response = request({
            Url = url,
            Method = "GET",
        })

        local statusCode = response and (response.StatusCode or response.Status)
        local body = response and (response.Body or response.body)

        if statusCode == 200 and body then
            return body
        end

        error("Falha HTTP ao buscar módulo: " .. tostring(url) .. " | status=" .. tostring(statusCode))
    end

    if game and game.HttpGet then
        return game:HttpGet(url)
    end

    error("Ambiente sem request() ou game:HttpGet() para carregar módulos por HTTP")
end

local function createHttpRequire(baseUrl)
    local normalizedBaseUrl = normalizeBaseUrl(baseUrl)

    local function httpRequire(moduleName)
        if moduleCache[moduleName] ~= nil then
            return moduleCache[moduleName]
        end

        local modulePath = moduleName:gsub("%.", "/") .. ".lua"
        local moduleUrl = normalizedBaseUrl .. modulePath

        local source = fetchModuleSource(moduleUrl)

        if source:sub(1, 3) == "\239\187\191" then
            source = source:sub(4)
        end

        local chunk, err = loadstring("local require = ...\n" .. source, "@" .. moduleUrl)
        if not chunk then
            error("Erro de compilação do módulo " .. moduleName .. ": " .. tostring(err))
        end

        local ok, result = pcall(chunk, httpRequire)
        if not ok then
            error("Erro ao executar módulo " .. moduleName .. ": " .. tostring(result))
        end

        moduleCache[moduleName] = result
        return result
    end

    return httpRequire
end

local requireModule = createHttpRequire(HttpLoader.baseUrl)
local App = requireModule("app")

return App.run()