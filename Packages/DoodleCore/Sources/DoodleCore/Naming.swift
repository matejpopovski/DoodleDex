/// Reads class names aloud in the guess panel. The model's labels are bare nouns.
public enum Naming {
    private static let bare: Set<String> = [
        "eyeglasses", "grapes", "headphones", "lightning", "pants", "scissors",
    ]

    public static func withArticle(_ category: String) -> String {
        if bare.contains(category) {
            return category
        }
        let startsWithVowelSound = category.first.map { "aeiou".contains($0) } ?? false
        return (startsWithVowelSound || category == "hourglass" ? "an " : "a ") + category
    }
}
