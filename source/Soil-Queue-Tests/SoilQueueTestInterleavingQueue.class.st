"
A queue that lets something happen right after it opens a transaction, once: what another
process does in the gap between the opening and whatever the queue does next.

Soil fixes what a transaction sees when it is opened, so the gap is where an older read
meets a newer state. The block decides what happens in it.
"
Class {
	#name : #SoilQueueTestInterleavingQueue,
	#superclass : #SoilQueue,
	#instVars : [
		'interleave'
	],
	#category : #'Soil-Queue-Tests'
}

{ #category : #accessing }
SoilQueueTestInterleavingQueue >> interleave: aBlock [
	"evaluated once, right after the next transaction I open is open"

	interleave := aBlock
]

{ #category : #running }
SoilQueueTestInterleavingQueue >> newTransaction [

	| txn |
	txn := super newTransaction.
	interleave ifNotNil: [ :aBlock |
		interleave := nil.
		aBlock value ].
	^ txn
]
