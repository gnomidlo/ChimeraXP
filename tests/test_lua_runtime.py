"""Run Lua scenarios via liblua5.4 when available (no Lua CLI required)."""
import ctypes
import ctypes.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class LuaSmoke(unittest.TestCase):
    def test_online_updater_mock(self):
        libpath = ctypes.util.find_library('lua5.4')
        if not libpath:
            self.skipTest('liblua5.4 not available')
        lua = ctypes.CDLL(libpath)
        lua.luaL_newstate.restype = ctypes.c_void_p
        lua.luaL_openlibs.argtypes = [ctypes.c_void_p]
        lua.luaL_loadfilex.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_char_p]
        lua.luaL_loadfilex.restype = ctypes.c_int
        lua.lua_pcallk.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_longlong, ctypes.c_void_p]
        lua.lua_pcallk.restype = ctypes.c_int
        lua.lua_tolstring.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_void_p]
        lua.lua_tolstring.restype = ctypes.c_char_p
        lua.lua_close.argtypes = [ctypes.c_void_p]
        import os
        cwd = os.getcwd()
        os.chdir(ROOT)
        L = lua.luaL_newstate()
        try:
            lua.luaL_openlibs(L)
            status = lua.luaL_loadfilex(L, b'tests/online_updater_mock.lua', None)
            if not status:
                status = lua.lua_pcallk(L, 0, -1, 0, 0, None)
            self.assertEqual(status, 0, (lua.lua_tolstring(L, -1, None) or b'').decode())
        finally:
            lua.lua_close(L)
            os.chdir(cwd)

if __name__ == '__main__':
    unittest.main()
