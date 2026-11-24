import SwiftUI

@main
struct GameApp: App {
    var body: some Scene { WindowGroup { ContentView() } }
}

struct ContentView: View {
    @State private var score = 0
    @State private var pos = CGPoint(x: 150, y: 300)

    var body: some View {
        GeometryReader { g in
            ZStack {
                Color.black.ignoresSafeArea()
                Text("النقاط: \(score)")
                    .font(.largeTitle)
                    .foregroundColor(.white)
                    .position(x: g.size.width / 2, y: 80)
                Circle()
                    .fill(Color.orange)
                    .frame(width: 70, height: 70)
                    .position(pos)
                    .onTapGesture {
                        score += 1
                        pos = CGPoint(
                            x: CGFloat.random(in: 50...(g.size.width - 50)),
                            y: CGFloat.random(in: 150...(g.size.height - 50)))
                    }
            }
        }
    }
}
