// 主线：七章，每章三件一定会发生的事（content/story.yaml，tools/build-content.mjs 校验后原样带进 CONTENT.story）。
// 这里先只有类型。怎么挑变体、纸带上的「下一件事」、章末强制发生，由引擎那一步接（见 story.yaml 文件头和 test/mainline.test.mjs 的挑法）。

type StoryScene = "building" | "street" | "river" | "primary" | "middle" | "across" | "away" | "newhome" | "rental" | "park" | "hospital";
type StorySlot = "morning" | "am" | "pm" | "evening" | "night";

interface StoryChapter {
  id: string;
  title: string;
  /** [起始岁, 结束岁]，章和章首尾相接 */
  ages: number[];
  /** 这一章新开的地图 */
  opens: StoryScene[];
  /** 章首那一句 */
  intro: string;
  /** 收尾的关口（落在这一章里，或下一章的头一天） */
  closes: string[];
}

interface StoryOption extends EventOption {
  /** 只看选的那个人自己的标记（同关口选项） */
  requires: { flags?: string[]; notFlags?: string[] };
  /** 选了花掉的积蓄 */
  cost?: number;
}

interface StoryEvent extends LifeEvent {
  chapter: number;
  beat: number;
  scene: StoryScene;
  slot: StorySlot;
  /** 纸带上「下一件事」 */
  next: string;
  /** 顶替随机池里的哪些旧事件 */
  replaces: string[];
  options: StoryOption[];
}

interface StoryContent {
  chapters: StoryChapter[];
  events: StoryEvent[];
}

interface Content { story: StoryContent }
