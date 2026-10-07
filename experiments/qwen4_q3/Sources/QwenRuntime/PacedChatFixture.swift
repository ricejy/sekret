import Foundation

/// Development fixture only. Generated assistant answers become subsequent history.
public enum PacedChatFixture {
    public static let system = "You are a concise on-device assistant. Answer the user's request directly. This is an evaluation using fictional data."
    public static let chatRequests = [
        "Draft an invitation of about 60 words for a fictional neighborhood seed exchange on Saturday at 10 am in Cedar Hall. Ask people to label their seed packets. Entry is free.",
        "Change it to Sunday at 11 am in Birch Hall. Keep the other details. Give only the revised invitation in about 60 words.",
        "Turn the latest invitation into exactly three short checklist items for an organizer. Include the current day, time, venue, packet-label instruction, and entry cost.",
        "What are the final day, time, venue, and entry cost? Answer in one sentence using the updates in this chat."
    ]
    public static let story = "Write a 180-word fictional story about a robot organizing imaginary seeds. Give it a beginning, a small problem, and a happy ending."
    public static let brief = makeBrief(recordCount: 40)
    public static func makeBrief(recordCount: Int) -> String {
        precondition((1...110).contains(recordCount))
        var lines = (1...recordCount).map { "Fictional project Cedar-\($0): coordinator Mira, room Cedar, review on 12 November, budget 200 credits. Its notes apply only to this project." }
        lines.insert("Fictional project Saffron: coordinator Niko, room Birch, review on 21 November, budget 735 credits. These are its final approved values.", at: recordCount / 2)
        return "Read these fictional project records.\n" + lines.joined(separator: "\n") + "\nFor project Saffron only, state coordinator, room, review date, and budget in one sentence. Do not use another project's values."
    }
    // Independently counted with the retained publisher tokenizer: 1884 / 3938.
    // With 128 reserved output tokens these fit 2048 / 4096 without truncation.
    public static let boundaryBriefs = [makeBrief(recordCount: 47), makeBrief(recordCount: 101)]
    // 1922+128 > 2048 and 3977+128 > 4096: must reject before context allocation.
    public static let overflowingBriefs = [makeBrief(recordCount: 48), makeBrief(recordCount: 102)]
    public static let extendedChatRequests = [
        "We are planning a fictional seed workshop: Saturday at 10 am, Cedar Hall, free entry, coordinator Mira. Attendees must label seed packets. Summarize in one sentence.",
        "Update the workshop to Sunday at 11 am in Birch Hall. Keep everything else unchanged. Summarize the current plan in one sentence.",
        "The organizer has a materials budget of 75 credits. This does not change the entry cost. Summarize the current plan in two short sentences.",
        "Niko replaces Mira as coordinator. Summarize the current plan in two short sentences, including the budget and entry cost.",
        "Add this accessibility detail: use the ramp at the side entrance. Summarize the current plan in two short sentences.",
        "Move the start time to noon on the same day. Everything else stays unchanged. Summarize the current plan in two short sentences.",
        "There will be 12 attendees, each bringing two seed packets. How many packets is that in total? Answer in one short sentence.",
        "Give the final day, start time, venue, coordinator, entry cost, materials budget, accessibility instruction, packet-label instruction, and expected total packets. Use only this chat and keep it under 100 words."
    ]
    public static let pauseSeconds = 30
}
