/// The credit the built-in drawings ask for (`Resources/Drawings`,
/// `Scripts/make-drawings.mjs`): the Twemoji graphics are licensed under
/// CC-BY 4.0, which asks that whoever shares them says whose they are, under
/// what licence, and that they were changed. Shown in Open Source Notices
/// beside libwebp's notice, which that file's own generator owns.
enum DrawingSetNotice {

    static let intro = "Ask's built-in drawings are Twemoji graphics, used under CC-BY 4.0."

    static let text: String = [
        "Twemoji graphics",
        "Copyright 2020 Twitter, Inc and other contributors.",
        "https://github.com/jdecked/twemoji",
        "",
        "Licensed under the Creative Commons Attribution 4.0 International",
        "licence (CC-BY 4.0): https://creativecommons.org/licenses/by/4.0/",
        "",
        "Photonz brings each drawing in as shapes you can edit, so a drawing",
        "you change is changed from the original.",
    ].joined(separator: "\n")
}
