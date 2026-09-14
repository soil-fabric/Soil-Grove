"
The third resumption semantics, the one that gets forgotten: I cannot simply be run
again, because an aborted attempt leaves something behind that has to go first. I count
both, so a test can tell that the cleanup ran and that it ran before the retry.
"
Class {
	#name : #SoilQueueTestCompensatingEntry,
	#superclass : #SoilQueueTestEntry,
	#instVars : [
		'compensationCount'
	],
	#category : #'Soil-Queue-Tests'
}

{ #category : #accessing }
SoilQueueTestCompensatingEntry class >> resumption [

	^ #compensating
]

{ #category : #accessing }
SoilQueueTestCompensatingEntry >> compensationCount [

	^ compensationCount
]

{ #category : #working }
SoilQueueTestCompensatingEntry >> compensateIn: aTransaction [

	compensationCount := compensationCount + 1
]

{ #category : #initialization }
SoilQueueTestCompensatingEntry >> initialize [

	super initialize.
	compensationCount := 0
]
