import Testing
import Foundation
import Models
@testable import AIFeature

@Suite("AudioPlayerModel")
@MainActor
struct AudioPlayerModelTests {

    // MARK: - Helpers

    private func makeRequest(
        bookId: String = "b1",
        bookTitle: String = "Atomic Habits",
        chapterNumber: Int = 1,
        chapterTitle: String = "Chapter 1",
        totalChapters: Int = 10
    ) -> AudioPlaybackRequest {
        AudioPlaybackRequest(
            bookId: bookId,
            bookTitle: bookTitle,
            bookAuthor: "James Clear",
            chapterNumber: chapterNumber,
            chapterTitle: chapterTitle,
            cover: nil,
            totalChapters: totalChapters
        )
    }

    // MARK: - Initial state

    @Test("Initial state: nothing playing")
    func initialState() {
        let model = AudioPlayerModel(repository: FakeAudioRepository())
        #expect(!model.hasActiveItem)
        #expect(!model.isPlaying)
        #expect(model.currentItem == nil)
        #expect(model.currentTime == 0)
        #expect(model.isLoading == false)
        #expect(model.loadError == nil)
    }

    // MARK: - Load and play

    @Test("loadAndPlay sets currentItem on success")
    func loadAndPlaySetsItem() async {
        let model = AudioPlayerModel(repository: FakeAudioRepository())
        await model.loadAndPlay(makeRequest())
        #expect(model.currentItem != nil)
        #expect(model.currentItem?.bookId == "b1")
        #expect(model.currentItem?.chapterNumber == 1)
        #expect(model.hasActiveItem)
        #expect(model.isLoading == false)
    }

    @Test("loadAndPlay sets loadError on repository failure")
    func loadAndPlaySetsErrorOnFailure() async {
        let repo = FakeAudioRepository(error: .offline)
        let model = AudioPlayerModel(repository: repo)
        await model.loadAndPlay(makeRequest())
        #expect(model.currentItem == nil)
        #expect(model.loadError != nil)
        if case .offline = model.loadError {
            // correct error type
        } else {
            Issue.record("Expected .offline error, got \(String(describing: model.loadError))")
        }
        #expect(!model.hasActiveItem)
    }

    @Test("loadAndPlay replaces an existing item")
    func loadAndPlayReplacesExistingItem() async {
        let model = AudioPlayerModel(repository: FakeAudioRepository())
        await model.loadAndPlay(makeRequest(bookId: "b1", bookTitle: "Book A"))
        #expect(model.currentItem?.bookTitle == "Book A")

        await model.loadAndPlay(makeRequest(bookId: "b2", bookTitle: "Book B", chapterNumber: 3))
        #expect(model.currentItem?.bookTitle == "Book B")
        #expect(model.currentItem?.chapterNumber == 3)
    }

    // MARK: - Play/pause

    @Test("togglePlayPause without item is a no-op")
    func toggleWithoutItemNoOp() {
        let model = AudioPlayerModel(repository: FakeAudioRepository())
        model.togglePlayPause()
        #expect(!model.isPlaying)
    }

    // MARK: - Seek

    @Test("seek clamps to valid range")
    func seekClampsToRange() async {
        let model = AudioPlayerModel(repository: FakeAudioRepository())
        await model.loadAndPlay(makeRequest())
        model.duration = 300
        model.seek(to: -10)
        #expect(model.currentTime == 0)
        model.seek(to: 999)
        #expect(model.currentTime == 300)
        model.seek(to: 150)
        #expect(model.currentTime == 150)
    }

    // MARK: - Skip

    @Test("skip forward adds seconds")
    func skipForward() async {
        let model = AudioPlayerModel(repository: FakeAudioRepository())
        await model.loadAndPlay(makeRequest())
        model.duration = 300
        model.currentTime = 60
        model.skip(seconds: 15)
        #expect(model.currentTime == 75)
    }

    @Test("skip backward subtracts seconds and floors at 0")
    func skipBackward() async {
        let model = AudioPlayerModel(repository: FakeAudioRepository())
        await model.loadAndPlay(makeRequest())
        model.duration = 300
        model.currentTime = 5
        model.skip(seconds: -15)
        #expect(model.currentTime == 0)
    }

    // MARK: - Playback rate

    @Test("setPlaybackRate stores the rate")
    func setPlaybackRateStores() {
        let model = AudioPlayerModel(repository: FakeAudioRepository())
        model.setPlaybackRate(1.5)
        #expect(model.playbackRate == 1.5)
    }

    // MARK: - Sleep timer

    @Test("setSleepTimer sets a non-nil end date")
    func sleepTimerSetsDate() {
        let model = AudioPlayerModel(repository: FakeAudioRepository())
        model.setSleepTimer(minutes: 30)
        #expect(model.sleepTimerEndDate != nil)
    }

    @Test("setSleepTimer nil cancels the timer")
    func sleepTimerNilCancels() {
        let model = AudioPlayerModel(repository: FakeAudioRepository())
        model.setSleepTimer(minutes: 30)
        model.setSleepTimer(minutes: nil)
        #expect(model.sleepTimerEndDate == nil)
    }

    @Test("setSleepTimer zero minutes cancels the timer")
    func sleepTimerZeroMins() {
        let model = AudioPlayerModel(repository: FakeAudioRepository())
        model.setSleepTimer(minutes: 0)
        #expect(model.sleepTimerEndDate == nil)
    }

    // MARK: - Progress

    @Test("progress is 0 when duration is 0")
    func progressZeroWhenNoDuration() {
        let model = AudioPlayerModel(repository: FakeAudioRepository())
        model.duration = 0
        #expect(model.progress == 0)
    }

    @Test("progress is fractional position")
    func progressIsFraction() async {
        let model = AudioPlayerModel(repository: FakeAudioRepository())
        await model.loadAndPlay(makeRequest())
        model.currentTime = 50
        model.duration = 200
        #expect(model.progress == 0.25)
    }
}
