import SwiftUI

/// "I want this": the buyer picks a price, a spot and a time on one sheet, and it all
/// goes to the seller as one request in the chat (an offer when the price is lower).
struct WantItSheet: View {
    let title: String
    let sellerName: String
    let imageURL: String?
    let listedPrice: Double
    let spots: [CampusMeetupSpot]
    var isSending: Bool = false
    let onSend: (_ amount: Double, _ spot: CampusMeetupSpot, _ time: Date) -> Void

    @Environment(\.campusTheme) private var campusTheme

    private enum PriceChoice: Hashable {
        case listed
        case percentOff(Int)
        case custom
    }

    @State private var priceChoice: PriceChoice = .listed
    @State private var customPrice = ""
    @State private var spotId = ""
    @State private var timeChoice: Date?
    @State private var customTime: Date?
    @State private var showSpotList = false
    @State private var showTimePicker = false
    @State private var pickerDate = MeetupComposeView.nextDaytimeSlot()

    private let percentOptions = [10, 20]

    // MARK: Derived values

    private static func roundDown(_ value: Double) -> Double {
        value >= 10 ? value.rounded(.down) : (value * 100).rounded(.down) / 100
    }

    private func amount(for choice: PriceChoice) -> Double? {
        switch choice {
        case .listed:
            return listedPrice
        case .percentOff(let pct):
            return Self.roundDown(listedPrice * (1 - Double(pct) / 100))
        case .custom:
            return MoneyAmount.parse(customPrice)
        }
    }

    private var selectedAmount: Double? {
        guard let value = amount(for: priceChoice), value > 0, value <= listedPrice + 0.004 else { return nil }
        return value
    }

    private var isOffer: Bool {
        guard let selectedAmount else { return false }
        return selectedAmount < listedPrice - 0.004
    }

    private var selectedSpot: CampusMeetupSpot? {
        spots.first { $0.id == spotId }
    }

    /// The first three spots, plus the picked one if it came from "More spots".
    private var chipSpots: [CampusMeetupSpot] {
        var list = Array(spots.prefix(3))
        if let selectedSpot, !list.contains(selectedSpot) {
            list.insert(selectedSpot, at: 0)
            list.removeLast()
        }
        return list
    }

    private var quickTimes: [Date] {
        let cal = Calendar.current
        let first = MeetupComposeView.nextDaytimeSlot()
        var times = [first]
        if let later = cal.date(byAdding: .hour, value: 2, to: first),
           cal.isDate(later, inSameDayAs: first),
           cal.component(.hour, from: later) <= 20 {
            times.append(later)
        }
        let nextDay = cal.date(byAdding: .day, value: 1, to: first) ?? first
        if let noon = cal.date(bySettingHour: 12, minute: 0, second: 0, of: nextDay) {
            times.append(noon)
        }
        return times
    }

    private var selectedTime: Date? {
        timeChoice ?? customTime
    }

    private var canSend: Bool {
        selectedAmount != nil && selectedSpot != nil && selectedTime.map { $0 > Date() } == true && !isSending
    }

    private var summary: String {
        var parts: [String] = []
        if let selectedAmount { parts.append(MoneyAmount.label(selectedAmount)) }
        if let selectedSpot { parts.append(selectedSpot.name) }
        if let selectedTime { parts.append(Self.timeLabel(selectedTime)) }
        if parts.isEmpty { return "Pick a price, a spot and a time." }
        return parts.joined(separator: " · ")
    }

    static func timeLabel(_ date: Date) -> String {
        let cal = Calendar.current
        let time = DateFormatter()
        time.dateFormat = "h:mma"
        time.amSymbol = "am"
        time.pmSymbol = "pm"
        var t = time.string(from: date)
        if t.hasSuffix(":00am") || t.hasSuffix(":00pm") {
            t = t.replacingOccurrences(of: ":00", with: "")
        }
        if cal.isDateInToday(date) { return "Today \(t)" }
        if cal.isDateInTomorrow(date) { return "Tomorrow \(t)" }
        let day = DateFormatter()
        day.dateFormat = "EEE MMM d"
        return "\(day.string(from: date)) \(t)"
    }

    // MARK: Body

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                header

                section("1. Your price") {
                    HStack(spacing: 8) {
                        priceButton(.listed)
                        ForEach(percentOptions, id: \.self) { pct in
                            priceButton(.percentOff(pct))
                        }
                        priceButton(.custom)
                    }
                    if priceChoice == .custom {
                        HStack(spacing: 6) {
                            Text("$")
                                .font(Theme.syne(22, weight: .bold))
                                .foregroundStyle(campusTheme.textPrimary)
                            MoneyCentsField(text: $customPrice, fontSize: 22, textColor: campusTheme.textPrimary)
                                .frame(height: 30)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(campusTheme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(campusTheme.border, lineWidth: 1)
                        )
                    }
                    Text(priceHint)
                        .font(Theme.syne(12, weight: .medium))
                        .foregroundStyle(campusTheme.textMuted)
                }

                section("2. Where") {
                    FlowChips(spacing: 8) {
                        ForEach(chipSpots) { spot in
                            chip(spot.name, selected: spot.id == spotId) { spotId = spot.id }
                        }
                        if spots.count > 3 {
                            chip("More spots", selected: false) { showSpotList = true }
                        }
                    }
                }

                section("3. When") {
                    FlowChips(spacing: 8) {
                        ForEach(quickTimes, id: \.self) { time in
                            chip(Self.timeLabel(time), selected: timeChoice == time) {
                                timeChoice = time
                                customTime = nil
                            }
                        }
                        if let customTime {
                            chip(Self.timeLabel(customTime), selected: timeChoice == nil) {
                                timeChoice = nil
                            }
                        }
                        chip("Pick a time", selected: false) {
                            pickerDate = selectedTime ?? MeetupComposeView.nextDaytimeSlot()
                            showTimePicker = true
                        }
                    }
                }

                VStack(spacing: 10) {
                    Button {
                        guard let selectedAmount, let selectedSpot, let selectedTime else { return }
                        onSend(selectedAmount, selectedSpot, selectedTime)
                    } label: {
                        HStack(spacing: 8) {
                            if isSending { ProgressView().tint(.white) }
                            Text(isSending ? "Sending…" : (isOffer ? "Send offer & meetup" : "Send request"))
                                .font(Theme.syne(16, weight: .bold))
                        }
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(campusTheme.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .opacity(canSend || isSending ? 1 : 0.4)
                    }
                    .buttonStyle(BouncyButtonStyle(pressedScale: 0.98))
                    .disabled(!canSend)

                    Text(summary + (canSend ? ". You pay with Apple Pay when you meet." : ""))
                        .font(Theme.syne(12, weight: .medium))
                        .foregroundStyle(campusTheme.textMuted)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 24)
        }
        .background(campusTheme.background.ignoresSafeArea())
        .sheet(isPresented: $showSpotList) {
            spotList
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showTimePicker) {
            timePicker
                .presentationDetents([.medium])
        }
    }

    private var priceHint: String {
        if priceChoice == .custom, let value = MoneyAmount.parse(customPrice), value > listedPrice {
            return "That’s more than the listed price. Pick \(MoneyAmount.label(listedPrice)) instead."
        }
        return isOffer
            ? "Below \(MoneyAmount.label(listedPrice)), so it goes as an offer the seller can accept."
            : "Listed price. The seller just confirms the meetup."
    }

    private var header: some View {
        HStack(spacing: 12) {
            AsyncImage(url: URL(string: imageURL ?? "")) { img in
                img.resizable().scaledToFill()
            } placeholder: {
                campusTheme.elevatedSurface
            }
            .frame(width: 52, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title.isEmpty ? "Listing" : title)
                    .font(Theme.syne(16, weight: .bold))
                    .foregroundStyle(campusTheme.textPrimary)
                    .lineLimit(2)
                Text("\(sellerName) · listed at \(MoneyAmount.label(listedPrice))")
                    .font(Theme.syne(13, weight: .medium))
                    .foregroundStyle(campusTheme.textMuted)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    private func section<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label)
                .font(Theme.syne(13, weight: .bold))
                .foregroundStyle(campusTheme.textMuted)
            content()
        }
    }

    private func priceButton(_ choice: PriceChoice) -> some View {
        let selected = priceChoice == choice
        let label: String = {
            if choice == .custom { return "Other" }
            return amount(for: choice).map(MoneyAmount.label) ?? "–"
        }()
        return Button {
            priceChoice = choice
            if choice == .custom, customPrice.isEmpty {
                customPrice = MoneyAmount.formatted(listedPrice)
            }
        } label: {
            Text(label)
                .font(Theme.syne(15, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(selected ? Color.white : campusTheme.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(selected ? campusTheme.primary : campusTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(selected ? Color.clear : campusTheme.border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func chip(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(Theme.syne(14, weight: .semibold))
                .lineLimit(1)
                .foregroundStyle(selected ? Color.white : campusTheme.textPrimary)
                .padding(.horizontal, 14)
                .frame(height: 40)
                .background(selected ? campusTheme.primary : campusTheme.surface)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(selected ? Color.clear : campusTheme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var spotList: some View {
        NavigationStack {
            List(spots) { spot in
                Button {
                    spotId = spot.id
                    showSpotList = false
                } label: {
                    HStack {
                        Text(spot.name)
                            .font(Theme.syne(15, weight: .semibold))
                            .foregroundStyle(campusTheme.textPrimary)
                        Spacer()
                        if spot.id == spotId {
                            Image(systemName: "checkmark")
                                .foregroundStyle(campusTheme.textPrimary)
                        }
                    }
                }
            }
            .navigationTitle("Meetup spots")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showSpotList = false }
                }
            }
        }
    }

    private var timePicker: some View {
        NavigationStack {
            DatePicker(
                "Meetup time",
                selection: $pickerDate,
                in: Date()...(Calendar.current.date(byAdding: .day, value: 14, to: Date()) ?? Date()),
                displayedComponents: [.date, .hourAndMinute]
            )
            .datePickerStyle(.wheel)
            .labelsHidden()
            .padding()
            .navigationTitle("Pick a time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showTimePicker = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        customTime = pickerDate
                        timeChoice = nil
                        showTimePicker = false
                    }
                }
            }
        }
    }
}

/// Lays chips out left to right and wraps them onto new lines.
struct FlowChips: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: proposal.width ?? widest, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
