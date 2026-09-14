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

{ #category : #accessing }
SoilQueueTestRepeatingEntry class >> resumption [

	^ #repeating
]

{ #category : #working }
SoilQueueTestRepeatingEntry >> performIn: aTransaction [

	self target addEffect: #ran.
	^ #finished
]
