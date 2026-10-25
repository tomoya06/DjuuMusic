// 由 m.djuu.com 首页抽屉分类自动提取生成
import Foundation

struct DjuuCategory: Identifiable, Hashable {
    let id: Int
    let name: String
    var children: [DjuuCategory] = []
}

enum DjuuCatalog {
    static let categories: [DjuuCategory] = [
        DjuuCategory(id: 115, name: "独家舞曲", children: [
            DjuuCategory(id: 116, name: "Y鼓(Electro)"),
            DjuuCategory(id: 117, name: "福鼓(ProgHouse)"),
            DjuuCategory(id: 118, name: "咚鼓(FunkyHouse)"),
            DjuuCategory(id: 119, name: "外文"),
            DjuuCategory(id: 122, name: "越南鼓(Vina/Lak)"),
            DjuuCategory(id: 120, name: "CLUB"),
            DjuuCategory(id: 123, name: "棒丝(Mel/Bounce)"),
            DjuuCategory(id: 121, name: "DISCO"),
            DjuuCategory(id: 125, name: "BreakBeat / RnB"),
        ]),
        DjuuCategory(id: 1, name: "迪高串烧", children: [
            DjuuCategory(id: 13, name: "中文串烧"),
            DjuuCategory(id: 14, name: "外语串烧"),
            DjuuCategory(id: 96, name: "中英串烧"),
            DjuuCategory(id: 12, name: "喊麦串烧"),
        ]),
        DjuuCategory(id: 2, name: "慢摇串烧", children: [
            DjuuCategory(id: 16, name: "中文串烧"),
            DjuuCategory(id: 17, name: "外语串烧"),
            DjuuCategory(id: 98, name: "中英串烧"),
            DjuuCategory(id: 97, name: "酒吧串烧"),
            DjuuCategory(id: 15, name: "喊麦串烧"),
        ]),
        DjuuCategory(id: 3, name: "慢歌串烧", children: [
            DjuuCategory(id: 18, name: "中文慢歌"),
            DjuuCategory(id: 19, name: "外语慢歌"),
            DjuuCategory(id: 20, name: "中英慢歌"),
        ]),
        DjuuCategory(id: 4, name: "中文Remix", children: [
            DjuuCategory(id: 21, name: "Club"),
            DjuuCategory(id: 22, name: "Electro"),
            DjuuCategory(id: 26, name: "ProgHouse"),
            DjuuCategory(id: 107, name: "Vina/LakHouse"),
            DjuuCategory(id: 99, name: "FunkyHouse"),
            DjuuCategory(id: 25, name: "Melbourne"),
            DjuuCategory(id: 24, name: "Bounce/ElectroBounce"),
            DjuuCategory(id: 23, name: "ElectroHouse"),
            DjuuCategory(id: 41, name: "车载版"),
            DjuuCategory(id: 27, name: "另类..."),
        ]),
        DjuuCategory(id: 5, name: "外文Remix", children: [
            DjuuCategory(id: 28, name: "中国风(Prog/Fk)"),
            DjuuCategory(id: 110, name: "越南鼓(Vina/Lak)"),
            DjuuCategory(id: 124, name: "新弹跳(Mel/Bounce)"),
            DjuuCategory(id: 29, name: "车载版"),
        ]),
        DjuuCategory(id: 6, name: "HOUSE", children: [
            DjuuCategory(id: 30, name: "Electro/Vina/Bass"),
            DjuuCategory(id: 31, name: "Bounce/K-Bounce"),
            DjuuCategory(id: 36, name: "DeepHouse"),
            DjuuCategory(id: 100, name: "FunkyHouse"),
            DjuuCategory(id: 35, name: "ProgHouse"),
            DjuuCategory(id: 38, name: "BounceHouse"),
            DjuuCategory(id: 33, name: "ElectroDutch"),
            DjuuCategory(id: 32, name: "ElectroMelbourne"),
            DjuuCategory(id: 34, name: "Speed/ClubHouse"),
            DjuuCategory(id: 37, name: "TechHouse/Vocal"),
            DjuuCategory(id: 39, name: "Nudisco/DiscoHouse"),
            DjuuCategory(id: 40, name: "Future/Bigroom/Edm"),
            DjuuCategory(id: 42, name: "另类风格..."),
        ]),
        DjuuCategory(id: 7, name: "霓虹风格", children: [
            DjuuCategory(id: 43, name: "HipHop"),
            DjuuCategory(id: 94, name: "RnB"),
            DjuuCategory(id: 44, name: "Funky/Rap"),
            DjuuCategory(id: 48, name: "Trap"),
            DjuuCategory(id: 50, name: "Rock"),
            DjuuCategory(id: 49, name: "Pop"),
            DjuuCategory(id: 45, name: "Reggae/Moombah"),
            DjuuCategory(id: 46, name: "Dubstep"),
            DjuuCategory(id: 47, name: "DanceHall"),
            DjuuCategory(id: 95, name: "BreakBeat"),
            DjuuCategory(id: 51, name: "暖场"),
            DjuuCategory(id: 52, name: "蓝调"),
            DjuuCategory(id: 53, name: "中文"),
            DjuuCategory(id: 54, name: "更多..."),
        ]),
        DjuuCategory(id: 8, name: "Mashup", children: [
            DjuuCategory(id: 55, name: "Mashup"),
            DjuuCategory(id: 56, name: "PartyBreak"),
            DjuuCategory(id: 108, name: "E.D.M"),
            DjuuCategory(id: 57, name: "Remixes"),
            DjuuCategory(id: 58, name: "变速/反差"),
            DjuuCategory(id: 59, name: "更多..."),
        ]),
        DjuuCategory(id: 9, name: "中文DISCO", children: [
            DjuuCategory(id: 60, name: "Hard"),
            DjuuCategory(id: 61, name: "DISCO"),
        ]),
        DjuuCategory(id: 10, name: "外文DISCO", children: [
            DjuuCategory(id: 114, name: "Hard"),
            DjuuCategory(id: 62, name: "Disco/PopDance"),
            DjuuCategory(id: 63, name: "PopTechno"),
            DjuuCategory(id: 64, name: "Techno/Trance"),
            DjuuCategory(id: 65, name: "更多..."),
        ]),
    ]
}