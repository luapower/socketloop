
	--timer API
	local t1 = {} --{{t1, thread1}, ...}

	function loop.sleep(timeout, thread)
		table.insert(t1, {socket.gettime() + timeout, thread})
		suspend()
	end

	local function min_timeout()
		if #t1 == 0 then return 0 end
		table.sort(t1, function(a, b) return a[1] > b[1] end)
		return t1[#t1][1] - socket.gettime()
	end

	local function wake_sleepers()
		local t0 = socket.gettime()
		local i = 1
		while i <= #t1 do
			local t, thread = t1[i][1], t1[i][2]
			if t - t0 - timeout_delta < 0 then
				table.remove(t1, i)
				resume(thread)
				i = i + 1
			else
				break
			end
		end
	end

