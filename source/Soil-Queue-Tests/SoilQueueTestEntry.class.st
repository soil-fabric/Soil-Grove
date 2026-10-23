"
A concrete entry that fills in the seam with the least a subclass can get away with: it
counts its runs and reports #finished. That is enough to show what the base does and
does not do, and several test entries build on it.

I am a repeating entry, the kind whose promise is idempotence -- counting a run is
idempotent in the only sense that matters here, because nothing outside me sees it.
"
Class {
	#name : #SoilQueueTestEntry,
	#superclass : #SoilQueueEntry,
	#instVars : [
		'runCount'
	],
	#category : #'Soil-Queue-Tests'
}

{ #category : #initialization }
SoilQueueTestEntry >> initialize [

	super initialize.
	runCount := 0
]

{ #category : #working }
SoilQueueTestEntry >> performIn: aTransaction [

	runCount := runCount + 1.
	^ #finished
]

{ #category : #working }
SoilQueueTestEntry >> resumeAfterAbortIn: aTransaction [
	"repeating: I run again from the start, and counting a run is idempotent in the only
	sense that matters here. Nothing to put right"
]

{ #category : #accessing }
SoilQueueTestEntry >> runCount [

	^ runCount
]
