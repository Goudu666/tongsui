// 由 tools/build-content.mjs 生成，请修改 content/events/*.yaml 后运行 npm run content
var CONTENT_EVENTS: LifeEvent[] = [
  {
    "id": "c_firefly",
    "kind": "mirror",
    "stage": "childhood",
    "seasons": [
      "summer"
    ],
    "weight": 3,
    "requires": {},
    "title": "萤火虫",
    "text": "傍晚，巷口的草丛里亮起了一点光。隔壁的窗户也\"吱呀\"一声开了。",
    "options": [
      {
        "id": "catch",
        "text": "拿玻璃瓶去装",
        "tags": [
          "adventure"
        ],
        "effects": {
          "self": {
            "heart": 1
          },
          "other": {},
          "bond": {},
          "flags": []
        }
      },
      {
        "id": "watch",
        "text": "蹲下来，就这么看着",
        "tags": [
          "gentle"
        ],
        "effects": {
          "self": {
            "heart": 2
          },
          "other": {},
          "bond": {},
          "flags": []
        }
      },
      {
        "id": "stay",
        "text": "算了，作业还没写完",
        "tags": [
          "solitude"
        ],
        "effects": {
          "self": {
            "mind": 1
          },
          "other": {},
          "bond": {},
          "flags": []
        }
      }
    ],
    "resonance": {
      "catch": {
        "text": "你们几乎同时冲出门，撞在一起。那天晚上，窗台上多了一瓶会发光的夏天。",
        "memory": "一瓶萤火虫",
        "bond": {
          "sync": 3,
          "close": 2
        }
      },
      "watch": {
        "text": "你们在草丛边并排蹲了很久，谁都没有说话，腿麻了也没动。",
        "memory": "那晚的光",
        "bond": {
          "sync": 3,
          "close": 3
        }
      },
      "stay": {
        "text": "两扇窗都亮着台灯。你们隔着一米宽的缝，各写各的作业。",
        "memory": "两盏台灯",
        "bond": {
          "sync": 2,
          "close": 1
        }
      }
    },
    "dissonance": {
      "text": "那晚，你们一个追着光跑远了，一个留在原地。",
      "bond": {
        "close": 1
      }
    }
  },
  {
    "id": "c_well_secret",
    "kind": "mirror",
    "stage": "childhood",
    "seasons": [],
    "weight": 2,
    "requires": {
      "minAge": 6
    },
    "title": "井边的秘密",
    "text": "巷子尽头的老井旁，你们发现了一只受伤的小猫。大人说过不许靠近那口井。",
    "options": [
      {
        "id": "hide",
        "text": "偷偷把它藏进柴房养起来",
        "tags": [
          "adventure",
          "gentle"
        ],
        "effects": {
          "self": {
            "heart": 1
          },
          "other": {},
          "bond": {},
          "flags": [
            "cat_secret"
          ]
        }
      },
      {
        "id": "tell",
        "text": "去告诉大人",
        "tags": [
          "responsible"
        ],
        "effects": {
          "self": {
            "mind": 1
          },
          "other": {},
          "bond": {},
          "flags": []
        }
      },
      {
        "id": "leave",
        "text": "不敢管，绕开走",
        "tags": [
          "solitude"
        ],
        "effects": {
          "self": {
            "heart": -1
          },
          "other": {},
          "bond": {},
          "flags": []
        }
      }
    ],
    "resonance": {
      "hide": {
        "text": "从那天起，你们有了第一个只属于两个人的秘密。猫叫\"井井\"。",
        "memory": "井井",
        "bond": {
          "sync": 3,
          "close": 4
        }
      },
      "tell": {
        "text": "你们一起去敲了大人的门。小猫后来被修车铺的爷爷收养了。",
        "memory": "修车铺的猫",
        "bond": {
          "sync": 2,
          "close": 2
        }
      }
    },
    "dissonance": {
      "text": "一个想留下它，一个想交给大人。你们第一次为一件事争了起来。",
      "bond": {
        "close": -1
      }
    }
  },
  {
    "id": "c_new_year",
    "kind": "mirror",
    "stage": "childhood",
    "seasons": [
      "winter"
    ],
    "weight": 2,
    "requires": {},
    "title": "除夕的鞭炮",
    "text": "除夕夜，你攥着一根偷来的火柴，口袋里有三个小鞭炮。",
    "options": [
      {
        "id": "together",
        "text": "去敲隔壁的窗，一起放",
        "tags": [
          "adventure"
        ],
        "effects": {
          "self": {
            "heart": 2
          },
          "other": {},
          "bond": {},
          "flags": []
        }
      },
      {
        "id": "save",
        "text": "留到明天早上",
        "tags": [
          "patient"
        ],
        "effects": {
          "self": {
            "mind": 1
          },
          "other": {},
          "bond": {},
          "flags": []
        }
      }
    ],
    "resonance": {
      "together": {
        "text": "两扇窗同时打开。\"砰\"的一声，你们的眉毛都被烧掉了一点。",
        "memory": "烧掉的眉毛",
        "bond": {
          "sync": 3,
          "close": 3
        }
      },
      "save": {
        "text": "大年初一的清晨，巷子里只有你们两个人的鞭炮声。",
        "memory": "初一的清晨",
        "bond": {
          "sync": 3,
          "close": 2
        }
      }
    },
    "dissonance": {
      "text": "你敲了窗，没人应。那年的鞭炮声是一个人听的。",
      "bond": {
        "close": 0
      }
    }
  },
  {
    "id": "c_plum_bloom",
    "kind": "mirror",
    "stage": "childhood",
    "seasons": [
      "spring"
    ],
    "weight": 1,
    "requires": {},
    "title": "老梅开了",
    "text": "巷口那棵老梅树开花了。有人说，在树下埋一样东西，许的愿就会实现。",
    "options": [
      {
        "id": "bury",
        "text": "埋下最喜欢的一颗弹珠",
        "tags": [
          "gentle"
        ],
        "effects": {
          "self": {
            "heart": 1
          },
          "other": {},
          "bond": {},
          "flags": [
            "plum_buried"
          ]
        }
      },
      {
        "id": "climb",
        "text": "爬上去摘一枝最高的",
        "tags": [
          "adventure"
        ],
        "effects": {
          "self": {
            "body": 1
          },
          "other": {},
          "bond": {},
          "flags": []
        }
      }
    ],
    "resonance": {
      "bury": {
        "text": "你们把东西埋在了同一个树根下，约好不告诉对方许了什么。",
        "memory": "梅树下的约定",
        "bond": {
          "sync": 4,
          "close": 3
        }
      },
      "climb": {
        "text": "两个人一起摔了下来，一人一枝梅花，一人一块淤青。",
        "memory": "最高的那枝梅",
        "bond": {
          "sync": 3,
          "close": 2
        }
      }
    },
    "dissonance": {
      "text": "一个在树下挖坑，一个在树上喊\"让开\"。花瓣落了一地。",
      "bond": {
        "close": 1
      }
    }
  },
  {
    "id": "c_first_fight",
    "kind": "solo",
    "stage": "childhood",
    "seasons": [],
    "weight": 2,
    "requires": {
      "minAge": 7
    },
    "title": "第一次打架",
    "text": "放学路上，几个高年级的孩子拦住了你，说你\"整天和隔壁那个小孩玩，丢人\"。",
    "options": [
      {
        "id": "fight",
        "text": "冲上去",
        "tags": [
          "adventure",
          "competitive"
        ],
        "effects": {
          "self": {
            "body": 1,
            "heart": -1
          },
          "other": {
            "heart": 1
          },
          "bond": {
            "close": 2
          },
          "flags": []
        }
      },
      {
        "id": "run",
        "text": "跑回家",
        "tags": [
          "solitude"
        ],
        "effects": {
          "self": {
            "heart": -1
          },
          "other": {},
          "bond": {},
          "flags": []
        }
      },
      {
        "id": "argue",
        "text": "和他们讲道理",
        "tags": [
          "responsible"
        ],
        "effects": {
          "self": {
            "mind": 1,
            "charm": 1
          },
          "other": {},
          "bond": {},
          "flags": []
        }
      }
    ],
    "resonance": null,
    "dissonance": null
  },
  {
    "id": "c_rainy_day",
    "kind": "solo",
    "stage": "childhood",
    "seasons": [],
    "weight": 3,
    "requires": {},
    "title": "下雨天",
    "text": "雨下了一整天，哪儿也去不了。",
    "options": [
      {
        "id": "read",
        "text": "翻出一本没看完的连环画",
        "tags": [
          "solitude"
        ],
        "effects": {
          "self": {
            "mind": 1
          },
          "other": {},
          "bond": {},
          "flags": []
        }
      },
      {
        "id": "puddle",
        "text": "穿上雨靴去踩水坑",
        "tags": [
          "adventure"
        ],
        "effects": {
          "self": {
            "body": 1,
            "heart": 1
          },
          "other": {},
          "bond": {},
          "flags": []
        }
      },
      {
        "id": "window",
        "text": "隔着窗缝和隔壁比赛吹泡泡",
        "tags": [
          "gentle"
        ],
        "effects": {
          "self": {
            "heart": 1
          },
          "other": {
            "heart": 1
          },
          "bond": {
            "close": 1
          },
          "flags": []
        }
      }
    ],
    "resonance": null,
    "dissonance": null
  },
  {
    "id": "c_guitar",
    "kind": "solo",
    "stage": "childhood",
    "seasons": [],
    "weight": 1,
    "requires": {
      "minAge": 8
    },
    "title": "修车铺的旧吉他",
    "text": "修车铺爷爷的墙上挂着一把落满灰的吉他。他说，想学就来。",
    "options": [
      {
        "id": "learn",
        "text": "每天放学去学一会儿",
        "tags": [
          "patient"
        ],
        "effects": {
          "self": {
            "charm": 1,
            "heart": 1
          },
          "other": {},
          "bond": {},
          "flags": [
            "guitar"
          ]
        }
      },
      {
        "id": "skip",
        "text": "算了，手指会疼",
        "tags": [
          "solitude"
        ],
        "effects": {
          "self": {},
          "other": {},
          "bond": {},
          "flags": []
        }
      }
    ],
    "resonance": null,
    "dissonance": null
  },
  {
    "id": "c_exam",
    "kind": "solo",
    "stage": "childhood",
    "seasons": [],
    "weight": 2,
    "requires": {
      "minAge": 9
    },
    "title": "期末考试",
    "text": "明天期末考试，你的数学还有两个单元没看。",
    "options": [
      {
        "id": "cram",
        "text": "熬夜看书",
        "tags": [
          "competitive"
        ],
        "effects": {
          "self": {
            "mind": 2,
            "body": -1
          },
          "other": {},
          "bond": {},
          "flags": []
        }
      },
      {
        "id": "ask",
        "text": "去隔壁问题目",
        "tags": [
          "gentle"
        ],
        "effects": {
          "self": {
            "mind": 1
          },
          "other": {},
          "bond": {
            "close": 1
          },
          "flags": []
        }
      },
      {
        "id": "sleep",
        "text": "早点睡，听天由命",
        "tags": [
          "solitude"
        ],
        "effects": {
          "self": {
            "heart": 1
          },
          "other": {},
          "bond": {},
          "flags": []
        }
      }
    ],
    "resonance": null,
    "dissonance": null
  },
  {
    "id": "t_note",
    "kind": "mirror",
    "stage": "teen",
    "seasons": [],
    "weight": 2,
    "requires": {},
    "title": "课本上的纸条",
    "text": "上课时，一张纸条从后排传了过来，上面只有一个问号。",
    "options": [
      {
        "id": "reply",
        "text": "在问号后面画一个笑脸",
        "tags": [
          "gentle"
        ],
        "effects": {
          "self": {
            "heart": 1
          },
          "other": {},
          "bond": {},
          "flags": []
        }
      },
      {
        "id": "ignore",
        "text": "认真听课，假装没看见",
        "tags": [
          "responsible"
        ],
        "effects": {
          "self": {
            "mind": 1
          },
          "other": {},
          "bond": {},
          "flags": []
        }
      }
    ],
    "resonance": {
      "reply": {
        "text": "那张纸条来回传了一整节课，最后变成一整页的小人。",
        "memory": "一整页的小人",
        "bond": {
          "sync": 3,
          "close": 2
        }
      }
    },
    "dissonance": {
      "text": "纸条在课桌角上躺了一节课。下课时，它不见了。",
      "bond": {
        "close": -1
      }
    }
  },
  {
    "id": "t_choose_school",
    "kind": "solo",
    "stage": "teen",
    "seasons": [],
    "weight": 2,
    "requires": {
      "minAge": 15
    },
    "title": "志愿",
    "text": "中考志愿表发下来了。城里的重点高中要住校，离巷子很远。",
    "options": [
      {
        "id": "far",
        "text": "报城里的重点",
        "tags": [
          "competitive"
        ],
        "effects": {
          "self": {
            "mind": 2
          },
          "other": {},
          "bond": {
            "distance": 1
          },
          "flags": []
        }
      },
      {
        "id": "near",
        "text": "报家门口的学校",
        "tags": [
          "gentle"
        ],
        "effects": {
          "self": {
            "heart": 1
          },
          "other": {},
          "bond": {},
          "flags": []
        }
      }
    ],
    "resonance": null,
    "dissonance": null
  },
  {
    "id": "y_letter_city",
    "kind": "solo",
    "stage": "young",
    "seasons": [],
    "weight": 2,
    "requires": {},
    "title": "另一座城市",
    "text": "一家外地的公司给了你一份工作，工资是现在的两倍。",
    "options": [
      {
        "id": "go",
        "text": "去",
        "tags": [
          "adventure",
          "competitive"
        ],
        "effects": {
          "self": {
            "charm": 1,
            "heart": -1
          },
          "other": {},
          "bond": {
            "distance": 2
          },
          "flags": []
        }
      },
      {
        "id": "stay",
        "text": "留下",
        "tags": [
          "gentle"
        ],
        "effects": {
          "self": {
            "heart": 1
          },
          "other": {},
          "bond": {},
          "flags": []
        }
      }
    ],
    "resonance": null,
    "dissonance": null
  },
  {
    "id": "m_demolish",
    "kind": "mirror",
    "stage": "middle",
    "seasons": [],
    "weight": 1,
    "requires": {},
    "title": "拆迁通知",
    "text": "巷口贴出了拆迁通知。老梅树也在红线里。",
    "options": [
      {
        "id": "dig",
        "text": "回去把树下的东西挖出来",
        "tags": [
          "gentle"
        ],
        "effects": {
          "self": {
            "heart": 1
          },
          "other": {},
          "bond": {},
          "flags": []
        }
      },
      {
        "id": "let_go",
        "text": "让它留在那里吧",
        "tags": [
          "solitude"
        ],
        "effects": {
          "self": {
            "heart": -1
          },
          "other": {},
          "bond": {},
          "flags": []
        }
      }
    ],
    "resonance": {
      "dig": {
        "text": "你们隔了很多年，在同一个周末回到了巷子，在同一个树根下碰了面。",
        "memory": "拆迁前的周末",
        "bond": {
          "sync": 4,
          "close": 4,
          "distance": -1
        }
      }
    },
    "dissonance": {
      "text": "树下只挖出了一样东西。另一样，大概永远留在了那里。",
      "bond": {
        "close": 0
      }
    }
  },
  {
    "id": "o_last_letter",
    "kind": "solo",
    "stage": "old",
    "seasons": [],
    "weight": 1,
    "requires": {},
    "title": "最后一封信",
    "text": "你翻出一叠旧信。有一封，当年写好了却没有寄出去。",
    "options": [
      {
        "id": "send",
        "text": "现在寄出去",
        "tags": [
          "gentle"
        ],
        "effects": {
          "self": {
            "heart": 2
          },
          "other": {
            "heart": 2
          },
          "bond": {
            "close": 2
          },
          "flags": []
        }
      },
      {
        "id": "keep",
        "text": "放回抽屉",
        "tags": [
          "solitude"
        ],
        "effects": {
          "self": {
            "heart": -1
          },
          "other": {},
          "bond": {},
          "flags": []
        }
      }
    ],
    "resonance": null,
    "dissonance": null
  }
];
