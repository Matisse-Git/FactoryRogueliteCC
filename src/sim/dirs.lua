-- Grid directions: 0 = east, 1 = south, 2 = west, 3 = north (y grows downward).
local D = {}
D.DX = { [0] = 1, [1] = 0, [2] = -1, [3] = 0 }
D.DY = { [0] = 0, [1] = 1, [2] = 0, [3] = -1 }
D.NAME = { [0] = 'EAST', [1] = 'SOUTH', [2] = 'WEST', [3] = 'NORTH' }

function D.opp(d) return (d + 2) % 4 end
function D.left(d) return (d + 3) % 4 end
function D.right(d) return (d + 1) % 4 end

return D
