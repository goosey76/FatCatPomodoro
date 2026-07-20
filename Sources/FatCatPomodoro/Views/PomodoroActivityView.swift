import SwiftUI

struct PomodoroActivityView: View {
    let completed: Int
    let goal: Int = 8 // Default goal of 8 pomodoros
    
    var body: some View {
        HStack(spacing: 6) {
            if completed <= goal {
                // Individual Dots
                ForEach(0..<goal, id: \.self) { index in
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
            } else {
                // Condensed Score Representation (e.g. "9 ●")
                Text("\(completed)")
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundColor(.orange)
                
                Circle()
                    .fill(Color.orange)
                    .frame(width: 8, height: 8)
                    .shadow(color: Color.orange.opacity(0.6), radius: 4)
                    .overlay {
                        Circle()
                            .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                            .scaleEffect(1.2)
                    }
            }
        }
        .padding(.vertical, 8)
    }
}
