"
A flaky entry that waits the same ten minutes after every failure instead of taking the
description's curve -- the way one kind of work can differ from the others on the same
queue.
"
Class {
	#name : #SoilQueueTestPatientEntry,
	#superclass : #SoilQueueTestFlakyEntry,
	#category : #'Soil-Queue-Tests'
}

{ #category : #working }
SoilQueueTestPatientEntry >> retryDelayAfter: anInteger under: aLane [

	^ 10 minutes
]
