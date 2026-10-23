"
The second resumption semantics: run again from the start, on a promise of idempotence.

I keep no note of how far I got, and I need none. What makes a repetition harmless is the
receiver of the effect, never the queue -- the queue's promise is at least once, and a
test can count on my target how often that once was.
"
Class {
	#name : #SoilQueueTestRepeatingEntry,
	#superclass : #SoilQueueEntry,
	#category : #'Soil-Queue-Tests'
}

{ #category : #working }
SoilQueueTestRepeatingEntry >> performIn: aTransaction [

	self target addEffect: #ran.
	^ #finished
]

{ #category : #working }
SoilQueueTestRepeatingEntry >> resumeAfterAbortIn: aTransaction [
	"repeating: I run again from the start, and my target counts how often. Nothing to put
	right -- the second effect is what a test of me is there to see"
]
