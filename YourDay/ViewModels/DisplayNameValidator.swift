import Foundation

/// Shared validator for display names. Used to block curse words and inappropriate language
/// in guest names, registration, and display name updates.
enum DisplayNameValidator {
    private static let blockedWords: [String] = [
        "anal", "anus", "arse", "ass", "asses", "asshole", "assholes", "asshat", "asswipe",
        "balls", "ballsack", "bastard", "bastards", "bitch", "bitches", "bitchy", "blowjob",
        "blowjobs", "boner", "boob", "boobs", "booby", "boobies", "bugger", "bum", "bummed",
        "butt", "butthole", "bullshit", "cock", "cocks", "cocky", "coon", "coons", "crap",
        "crappy", "cunt", "cunts", "cunty", "dick", "dicks", "dickhead", "dickheads", "dickwad",
        "dickweed", "dildo", "dildos", "dipshit", "dyke", "dykes", "dumbass", "fag", "faggot",
        "faggots", "fags", "fuck", "fucked", "fucker", "fuckers", "fucking", "fucks", "fuckface",
        "fuckboy", "fucktard", "fuk", "fck", "fuc", "genitals", "goddamn", "goddamnit", "hell",
        "homo", "homos", "jerk", "jizz", "jugs", "kike", "kikes", "knob", "knobs", "knockers",
        "labia", "masturbat", "masturbate", "masturbation", "motherfucker", "motherfucking",
        "nazi", "nazis", "nigga", "niggas", "nigger", "niggers", "niggr", "penis", "penises",
        "piss", "pissed", "pissy", "poop", "poops", "porn", "porno", "prick", "pricks", "pube",
        "pubes", "puss", "pussy", "pussies", "queer", "queers", "rape", "raped", "raper",
        "raping", "rapist", "rectum", "retard", "retarded", "retards", "rimjob", "rimjobs",
        "shit", "shits", "shitty", "shithead", "shitbag", "sht", "sh1t", "skank", "skanky",
        "slut", "sluts", "slutty", "smartass", "smegma", "spunk", "tit", "tits", "titty",
        "titties", "tosser", "tossers", "turd", "turds", "twat", "twats", "twatty", "vagina",
        "vaginas", "wank", "wanker", "wanking", "whore", "whores", "whorey", "hoe", "hoes",
        "ho", "hos", "thot", "thots", "wtf", "xxx", "handjob", "jackoff", "jerkoff", "cum",
        "cums", "semen", "testicle", "testicles", "scrotum", "vulva", "clitoris", "orgasm",
        "orgasms", "bondage", "bdsm", "fetish", "incest", "pedo", "pedophile", "pedophilia",
        "underage", "molest", "molested", "bestiality", "zoophilia", "necrophilia", "scat",
        "sodomy", "sodomize", "sodomized"
    ]

    /// Returns true if the given display name contains blocked/inappropriate language.
    /// Comparison is case-insensitive and uses whole-word matching to avoid false positives (e.g. "class").
    static func containsProfanity(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let lowercased = trimmed.lowercased()
        let words = lowercased.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        let blockedSet = Set(blockedWords)
        for word in words {
            if blockedSet.contains(word) {
                return true
            }
        }
        if blockedSet.contains(lowercased) { return true }
        return false
    }
}
