"
A compensating entry whose cleanup cannot be done: it throws. What a pass over the orphans
does with one that cannot be given back is what it is for.
"
Class {
	#name : #SoilQueueTestUncompensableEntry,
	#superclass : #SoilQueueTestCompensatingEntry,
	#category : #'Soil-Queue-Tests'
}

{ #category : #working }
SoilQueueTestUncompensableEntry >> compensateIn: aTransaction [

	self error: 'the cleanup cannot be done'
]
