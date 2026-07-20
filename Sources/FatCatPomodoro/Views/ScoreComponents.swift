import SwiftUI

// --- CAT ICON VIEW ---
struct CatIconView: View {
    let emoji: String
    let size: CGFloat

    var body: some View {
        if let path = Bundle.module.path(forResource: "face_cat", ofType: "png"),
           let nsImage = NSImage(contentsOfFile: path) {
            Image(nsImage: nsImage)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
        } else {
            Text(emoji)
                .font(.system(size: size))
        }
    }
}

// --- CAT COLLECTION VIEW ---
struct ScoreCatView: View {
    let completed: Int
    let goal: Int
    let catEmoji: String

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<goal, id: \.self) { index in
                if index < completed {
                    CatIconView(emoji: catEmoji, size: 24)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Circle()
                        .fill(Color.white.opacity(0.12))
                        .frame(width: 5, height: 5)
                }
            }
            if completed > goal {
                Text("+\(completed - goal)")
                    .font(.system(size: 8, weight: .black, design: .rounded))
                    .foregroundColor(.orange)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: completed)
    }
}

// --- DESIGN A: THE GRID ---
struct ScoreGridView: View {
    let completed: Int
    var goal: Int = 8
    
    var body: some View {
        VStack(spacing: 4) {
            ForEach(0..<4, id: \.self) { row in
                HStack(spacing: 4) {
                    ForEach(0..<2, id: \.self) { col in
                        let index = row * 2 + col
                        Circle()
                            .fill(index < completed ? Color.orange : Color.white.opacity(0.1))
                            .frame(width: 8, height: 8)
                            .shadow(color: index < completed ? Color.orange.opacity(0.6) : .clear, radius: 4)
                            .overlay {
                                if index < completed {
                                    Circle()
                                        .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                                        .scaleEffect(1.2)
                                }
                            }
                    }
                }
            }
            
            if completed > goal {
                Text("\(completed)")
                    .font(.system(size: 8, weight: .black))
                    .foregroundColor(.orange)
                    .padding(.top, 2)
            }
        }
    }
}

// --- DESIGN B: THE PILLAR ---
struct ScorePillarView: View {
    let completed: Int
    var goal: Int = 8
    
    var body: some View {
        VStack(spacing: 4) {
            Text("\(completed)")
                .font(.system(size: 10, weight: .black, design: .rounded))
                .foregroundColor(.orange)
            
            ZStack(alignment: .bottom) {
                // Background
                Capsule()
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 8, height: 48)
                
                // Fill
                Capsule()
                    .fill(
                        LinearGradient(colors: [.orange, .red], startPoint: .top, endPoint: .bottom)
                    )
                    .frame(width: 8, height: min(48, (CGFloat(completed) / CGFloat(max(1, goal))) * 48))
                    .shadow(color: Color.orange.opacity(0.5), radius: 4)
                    .overlay(alignment: .top) {
                        if completed > 0 {
                            Circle()
                                .fill(Color.white)
                                .frame(width: 4, height: 4)
                                .padding(.top, 2)
                        }
                    }
            }
        }
    }
}

// --- DESIGN C: THE ZEN RING ---
struct ScoreRingView: View {
    let completed: Int
    var goal: Int = 8
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.1), lineWidth: 3)
            
            Circle()
                .trim(from: 0, to: min(1.0, CGFloat(completed) / CGFloat(max(1, goal))))
                .stroke(
                    LinearGradient(colors: [.orange, .red], startPoint: .top, endPoint: .bottom),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: Color.orange.opacity(0.5), radius: 4)
            
            VStack(spacing: 0) {
                Text("\(completed)")
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                
                if completed >= goal {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 8))
                        .foregroundColor(.orange)
                }
            }
        }
        .frame(width: 40, height: 40)
    }
}
