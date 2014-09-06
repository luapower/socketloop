
--luasocket-based scheduler for Lua symmetric coroutines.
--Cosmin Apreutesei. Public domain.

local socket = require'socket'
local glue = require'glue'
local coro = require'coro'

local loop = {}

local read, write = {}, {} --{skt: thread}

local function wait(rwt,skt)
	rwt[skt] = coro.current
	coro.transfer(loop.thread)
	rwt[skt] = nil
end

local function accept(skt,...)
	wait(read,skt)
	return assert(skt:accept(...))
end

local function receive(skt,...)
	wait(read,skt)
	return skt:receive(...)
end

local function send(skt,...)
	wait(write,skt)
	return skt:send(...)
end

local function close(skt,...)
	write[skt] = nil
	read[skt] = nil
	return assert(skt:close(...))
end

--wrap a luasocket socket object into an object that performs socket
--operations asynchronously.
function loop.wrap(skt)
	local o = {socket = skt}
	--set async methods
	function o:accept(...) return loop.wrap(accept(skt,...)) end
	function o:receive(...) return receive(skt,...) end
	function o:send(...) return send(skt,...) end
	function o:close(...) return close(skt,...) end
	--forward other methods to skt
	local mt = getmetatable(skt).__index
   for name, method in pairs(mt) do
		if type(method) == 'function' and not o[name] then
			o[name] = function(self, ...)
				return method(skt, ...)
			end
		end
	end
	return o
end

function loop.connect(address, port, locaddr, locport)
	local skt = assert(socket.tcp())
	if locaddr or locport then
		assert(skt:bind(locaddr, locport or 0))
	end
	skt = loop.wrap(skt)
	return skt:connect(address, port)
end

local function wake(skt,rwt)
	local thread = rwt[skt]
	if not thread then return end
	coro.transfer(thread)
	--thread transfered back here either because it asked for a read or write or because it finished execution.
	--finishing execution implies closing the connection.
	if not read[skt] and not write[skt] then
		skt:close()
	end
end

--call select() and resume the calling threads of the sockets that get loaded.
function loop.dispatch(timeout)
	if not next(read) and not next(write) then return end
	local reads, writes, err = glue.keys(read), glue.keys(write)
	reads, writes, err = socket.select(reads, writes, timeout)
	loop.thread = coro.current
	for i=1,#reads do wake(reads[i], read) end
	for i=1,#writes do wake(writes[i], write) end
	return true
end

local stop = false
function loop.stop() stop = true end
function loop.start(timeout)
	while loop.dispatch(timeout) do
		if stop then break end
	end
end

--create a coro thread set up to transfer control to the loop thread on finish, and run it.
--return it while suspended in the first socket call. dispatch() will manage it next.
function loop.newthread(f, val)
	local loop_thread = loop.thread
	local thread = coro.create(f, loop_thread)
	loop.thread = coro.current
	coro.transfer(thread, val)
	loop.thread = loop_thread
	return thread
end

function loop.newserver(host, port, handler)
	local server_skt = socket.tcp()
	server_skt:settimeout(1)
	assert(server_skt:bind(host, port))
	assert(server_skt:listen(16384))
	server_skt = loop.wrap(server_skt)
	coro.transfer(coro.create(function()
		while true do
			local client_skt = server_skt:accept()
			loop.newthread(handler, client_skt)
		end
	end))
end

if not ... then
	socketloop_lib = 'socketloop_coro'
	require'socketloop_test'
end

return loop

