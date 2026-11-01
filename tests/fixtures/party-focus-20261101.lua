-- User GMCP snapshot: all four party members attack the same gnoll.
return {
  Char = {
    Info = {
      gender = "kobieta",
      id = "e72d4042788c06f9e-1",
      name = "Xochitl",
      race = "jaszczuroczlek"
    },
    Name = {
      name = "Xochitl"
    },
    Vitals = {
      encumbrance = 69,
      fatigue = 37,
      hp = 100,
      hunger = 77,
      mana = 100,
      progress = 13,
      thirst = 99
    }
  },
  Chimera = {
    Combat = {
      Kill = {
        by_self = 0,
        killer = {
          id = "e72d4042788c06f9e-169",
          kind = "player",
          name = "Trul",
          self = 0
        },
        room = "85b4e8613a0b575e",
        victim = {
          id = "e72d4042788c06f9e-106",
          kind = "npc",
          name = "Bury chudy zajac"
        }
      },
      State = {
        covers = { {
            guard = "e72d4042788c06f9e-169",
            guarded = "e72d4042788c06f9e-1"
          }, {
            guard = "e72d4042788c06f9e-1",
            guarded = "e72d4042788c06f9e-182"
          } },
        primary = "e72d4042788c06f9e-187",
        relations = { {
            attacker = "e72d4042788c06f9e-1",
            defender = "e72d4042788c06f9e-187"
          }, {
            attacker = "e72d4042788c06f9e-182",
            defender = "e72d4042788c06f9e-187"
          }, {
            attacker = "e72d4042788c06f9e-173",
            defender = "e72d4042788c06f9e-187"
          }, {
            attacker = "e72d4042788c06f9e-169",
            defender = "e72d4042788c06f9e-187"
          }, {
            attacker = "e72d4042788c06f9e-187",
            defender = "e72d4042788c06f9e-169"
          }, {
            attacker = "e72d4042788c06f9e-188",
            defender = "e72d4042788c06f9e-1"
          } },
        room = "61fd65530ce0255f"
      }
    },
    Group = {
      State = {
        leader = "e72d4042788c06f9e-1",
        members = { {
            here = 1,
            hp = 1838,
            id = "e72d4042788c06f9e-1",
            mana = 1060,
            maxhp = 1838,
            maxmana = 1060,
            maxstamina = 146,
            name = "Xochitl",
            self = 1,
            stamina = 93
          }, {
            here = 1,
            hp = 1649,
            id = "e72d4042788c06f9e-169",
            mana = 470,
            maxhp = 1700,
            maxmana = 470,
            maxstamina = 140,
            name = "Trul",
            self = 0,
            stamina = 92
          }, {
            here = 1,
            hp = 732,
            id = "e72d4042788c06f9e-173",
            mana = 690,
            maxhp = 820,
            maxmana = 690,
            maxstamina = 96,
            name = "Parmezan",
            self = 0,
            stamina = 82
          }, {
            here = 1,
            hp = 252,
            id = "e72d4042788c06f9e-182",
            mana = 240,
            maxhp = 300,
            maxmana = 240,
            maxstamina = 68,
            name = "Chasstana",
            self = 0,
            stamina = 54
          } }
      }
    },
    Room = {
      Entities = {
        entities = { {
            group_role = "leader",
            hp = 1838,
            id = "e72d4042788c06f9e-1",
            kind = "player",
            maxhp = 1838,
            name = "Xochitl",
            relation = "self",
            states = {}
          }, {
            group_role = "member",
            hp = 252,
            id = "e72d4042788c06f9e-182",
            kind = "npc",
            maxhp = 300,
            name = "Chasstana",
            relation = "ally",
            states = {}
          }, {
            group_role = "member",
            hp = 732,
            id = "e72d4042788c06f9e-173",
            kind = "player",
            maxhp = 820,
            name = "Parmezan",
            relation = "group",
            states = {}
          }, {
            group_role = "member",
            hp = 1649,
            id = "e72d4042788c06f9e-169",
            kind = "player",
            maxhp = 1700,
            name = "Trul",
            relation = "group",
            states = {}
          }, {
            group_role = "none",
            hp = 680,
            id = "e72d4042788c06f9e-187",
            kind = "npc",
            maxhp = 920,
            name = "Zwinny grozny gnoll",
            relation = "hostile",
            states = {}
          }, {
            group_role = "none",
            hp = 1080,
            id = "e72d4042788c06f9e-188",
            kind = "npc",
            maxhp = 1080,
            name = "Rosly wymalowany gnoll",
            relation = "hostile",
            states = {}
          } },
        room = "61fd65530ce0255f"
      }
    }
  },
  Core = {
    Info = {
      mudlib = "CDpl",
      server = "Chimera"
    }
  },
  Room = {
    Info = {
      area = "Las pod Beregost",
      area_id = "c51cdd43de735c50",
      exits = {
        polnoc = "5172aef15f3ceac1",
        ["polnocny-zachod"] = "8b39e96048763194",
        poludnie = "19939d0c75c7b195",
        ["poludniowy-zachod"] = "abeb4bd0d6099e5c",
        wschod = "3907b52c481e638f",
        zachod = "84d1dcf4a1a5b6ee"
      },
      id = "61fd65530ce0255f",
      indoors = 0,
      name = "W gestym lesie",
      terrain = "las"
    }
  }
}
