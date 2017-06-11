function love.conf(t)
	t.author			= "Xkeeper"
	t.version			= "0.10.1"
	t.console			= true
	t.modules.physics	= false
	t.modules.joystick	= false
	t.modules.graphics	= true
	t.modules.window	= true

	t.window.title		= "Stream Game"
	t.window.width		= 400
	t.window.height		= 460
end
