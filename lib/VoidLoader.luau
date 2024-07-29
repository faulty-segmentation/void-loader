--!strict

--[[
	Author: Segfault
	Date: 7/1/24

	VoidLoader is a basic module loader that initializes modules as services/controllers and provides support for lifecycle methods. 
	
	The following lifecycle methods are:
		- OnInit: Runs as soon as the service/controfller has been initialized. It is not safe to access other services/controllers in this lifecycle method.
		It's also recommended to not yield in this method as it will delay the other services/controllers from loaded. This does not apply to other lifecycle methods.
		
		- OnStart: Runs once every service/controller has been loaded.
		
		- OnUpdate: Runs every `RunService.Heartbeat`. Passes the delta time as an argument.
		
		- OnPhysics: Run every `RunService.Stepped`. Passes the delta time as an argument.
		
		- OnRender: Runs every `RunService.RenderStepped`. This method only works on controllers. If there is an `OnRender` method on a service, it will display a warning.
]]

--= Types =--

type InitFunction = () -> nil
type DeltaTimeFunction = (deltaTime: number) -> nil

type ServiceController = {
	OnInit: InitFunction?,
	OnStart: InitFunction?,
	OnUpdate: DeltaTimeFunction?,
	OnPhysics: DeltaTimeFunction?,
	OnRender: DeltaTimeFunction?
}

--= Services =--

local RunService = game:GetService("RunService")

--= Constants =--

local ALREADY_CONSUMED_ERROR = "The VoidLoader:Consume method has already been called."

--= Variables =--

local VoidLoader = {}

local consumedModules = false
local loadedModules: {[ModuleScript]: ServiceController} = {}

--= Private Functions =--

local function loadModuleScript(moduleScript: ModuleScript)
	-- Right now Luau's linter will complain if we don't supply a direct path to `require`.
	-- Surrounding `require` with paranthesis will silence it.
	local loadedModule = (require)(moduleScript)
	
	if type(loadedModule) == "table" then
		loadedModules[moduleScript] = loadedModule
	end
end

local function tryAddLifecycleMethodInPlace(currentMethods: {}, method)
	if type(method) == "function" then
		table.insert(currentMethods, method)
	end
end

--= Public Methods =--

--[[
	Returns whether VoidLoader has consumed the modules.
]]
function VoidLoader:DidConsumeModules()
	return consumedModules
end

--[[
	Loads all child modules under the provided instance. If `VoidLoader:Consume` has already been called, an error is thrown instead.
]]
function VoidLoader:LoadChildren(parentInstance: Instance)
	assert(not VoidLoader:DidConsumeModules(), ALREADY_CONSUMED_ERROR)
	
	for _, child in parentInstance:GetChildren() do
		if child:IsA("ModuleScript") then
			loadModuleScript(child)
		end
	end
end

--[[
	Loads all descendant modules under the provided instance. If `VoidLoader:Consume` has already been called, an error is thrown instead.
]]
function VoidLoader:LoadDescendants(parentInstance: Instance)
	assert(not VoidLoader:DidConsumeModules(), ALREADY_CONSUMED_ERROR)

	for _, descendant in parentInstance:GetDescendants() do
		if descendant:IsA("ModuleScript") then
			loadModuleScript(descendant)
		end
	end
end

--[[
	Initializes all loaded modules and their lifecycle methods. If `VoidLoader:Consume` has already been called, an error is thrown instead.
]]
function VoidLoader:Consume()
	assert(not VoidLoader:DidConsumeModules(), ALREADY_CONSUMED_ERROR)
	
	consumedModules = true
	
	local initMethods: {InitFunction} = {}
	local startMethods: {InitFunction} = {}
	local tickMethods: {DeltaTimeFunction} = {}
	local physicsMethods: {DeltaTimeFunction} = {}
	local renderMethods: {DeltaTimeFunction} = {}
	
	for moduleScript, loadedModule in loadedModules do
		tryAddLifecycleMethodInPlace(initMethods, loadedModule.OnInit)
		tryAddLifecycleMethodInPlace(startMethods, loadedModule.OnStart)
		tryAddLifecycleMethodInPlace(tickMethods, loadedModule.OnUpdate)
		tryAddLifecycleMethodInPlace(physicsMethods, loadedModule.OnPhysics)
		
		if type(loadedModule.OnRender) == "function" then
			if RunService:IsServer() then
				warn(`Did not load the OnRender method for {moduleScript.Name} as services do not support that lifecycle method.`)
			else
				table.insert(renderMethods, loadedModule.OnRender)
			end
		end
	end
	
	for _, initMethod in initMethods do
		initMethod()
	end
	
	RunService.Heartbeat:Connect(function(deltaTime)
		for _, tickMethod in tickMethods do
			tickMethod(deltaTime)
		end
	end)
	
	RunService.Stepped:Connect(function(deltaTime)
		for _, physicsMethod in physicsMethods do
			physicsMethod(deltaTime)
		end
	end)
	
	if RunService:IsClient() then
		RunService.RenderStepped:Connect(function(deltaTime)
			for _, renderMethod in renderMethods do
				renderMethod(deltaTime)
			end
		end)
	end
	
	for _, startMethod in startMethods do
		task.spawn(startMethod)
	end
	
	if RunService:IsClient() then
		print("VoidLoader has successfully started all controllers.")
	else
		print("VoidLoader has successfully started all services.")	
	end
end

return VoidLoader