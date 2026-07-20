import SwiftUI
import AppKit

struct HorizontalDialView: View {
    @Binding var value: Int // in minutes
    let range: ClosedRange<Int>
    let title: String
    
    @State private var internalId: Int?
    private let tickSpacing: CGFloat = 16
    private let majorTickHeight: CGFloat = 20
    private let minorTickHeight: CGFloat = 10
    
    var body: some View {
        VStack(spacing: 0) {
            Text(title.uppercased())
                .font(.system(size: 8, weight: .black))
                .foregroundColor(.white.opacity(0.3))
                .tracking(1)
                .padding(.bottom, 4)
            
            GeometryReader { geo in
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .bottom, spacing: 0) {
                            ForEach(range, id: \.self) { i in
                                let isMajor = (i % 5 == 0) || (i == range.lowerBound)
                                VStack(spacing: 4) {
                                    Rectangle()
                                        .fill(isMajor ? Color.white : Color.white.opacity(0.4))
                                        .frame(width: isMajor ? 2 : 1, 
                                               height: isMajor ? majorTickHeight : minorTickHeight)
                                    
                                    if isMajor {
                                        Text("\(i)")
                                            .font(.system(size: 10, weight: i == (internalId ?? value) ? .black : .bold))
                                            .foregroundColor(i == (internalId ?? value) ? .orange : .white.opacity(0.7))
                                            .fixedSize()
                                    } else {
                                        Text("")
                                            .font(.system(size: 10))
                                            .fixedSize()
                                    }
                                }
                                .frame(width: tickSpacing)
                                .id(i)
                                .scaleEffect(i == (internalId ?? value) ? 1.2 : 1.0)
                                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: internalId)
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .contentMargins(.horizontal, max(0, (geo.size.width - tickSpacing) / 2), for: .scrollContent)
                    .scrollTargetBehavior(.viewAligned)
                    .scrollPosition(id: $internalId)
                    .overlay(alignment: .center) {
                        VStack(spacing: 4) {
                            Text("\(internalId ?? value)")
                                .font(.system(size: 18, weight: .black, design: .rounded))
                                .foregroundColor(.orange)
                                .shadow(color: Color.orange.opacity(0.4), radius: 6)
                                .offset(y: -18)
                            
                            Capsule()
                                .fill(Color.orange)
                                .frame(width: 2, height: majorTickHeight + 8)
                        }
                        .offset(y: 6)
                    }
                    .mask {
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0),
                                .init(color: .black, location: 0.2),
                                .init(color: .black, location: 0.8),
                                .init(color: .clear, location: 1)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    }
                    .onAppear {
                        internalId = value
                        proxy.scrollTo(value, anchor: .center)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            proxy.scrollTo(value, anchor: .center)
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            proxy.scrollTo(value, anchor: .center)
                        }
                    }
                    .onChange(of: value) { _, newValue in
                        if internalId != newValue {
                            internalId = newValue
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                proxy.scrollTo(newValue, anchor: .center)
                            }
                        }
                    }
                    .onChange(of: internalId) { _, newId in
                        if let newId = newId, newId != value {
                            value = newId
                            if newId % 5 == 0 {
                                NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
                            } else {
                                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                            }
                        }
                    }
                }
            }
            .frame(height: 56)
        }
    }
}
