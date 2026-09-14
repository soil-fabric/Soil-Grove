"
A concrete entry that fills in the seam with the least a subclass can get away with: it
counts its runs and reports #finished. That is enough to show what the base does and
does not do, and it is the entry the other test subclasses build on.

I am #repeating, the semantics whose promise is idempotence -- counting a run is
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

{ #category : #accessing }
SoilQueueTestEntry class >> resumption [

	^ #repeating
]

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

{ #category : #accessing }
SoilQueueTestEntry >> runCount [

	^ runCount
]
