"
A queue that lets something happen right after one of the steps of a worker has committed,
once: what a transaction of somebody else does in the gap between two of the transactions
of one step, which share nothing but the key.

Unlike SoilQueueTestInterleavingQueue it acts after the step and not after the opening of
the next transaction. What a transaction sees is fixed when it opens, so the gap that is
wanted here -- a removal that is committed before the next transaction opens -- is not one
that can be made from inside the opening.
"
Class {
	#name : #SoilQueueTestRemovingQueue,
	#superclass : #SoilQueue,
	#instVars : [
		'afterAssigning',
		'afterClaiming'
	],
	#category : #'Soil-Queue-Tests'
}

{ #category : #'instance creation' }
SoilQueueTestRemovingQueue class >> from: aQueue [
	"the same queue, only with a gap. A live queue comes from its description, and the
	description knows one class to make"

	^ self basicNew
		copyFrom: aQueue;
		yourself
]

{ #category : #accessing }
SoilQueueTestRemovingQueue >> afterAssigning: aBlock [
	"evaluated once, with the key, right after the next entry is handed out"

	afterAssigning := aBlock
]

{ #category : #accessing }
SoilQueueTestRemovingQueue >> afterClaiming: aBlock [
	"evaluated once, with the key, right after the next claim has committed"

	afterClaiming := aBlock
]

{ #category : #working }
SoilQueueTestRemovingQueue >> assignNextIn: aLane preferring: aKey [

	| key |
	key := super assignNextIn: aLane preferring: aKey.
	key ifNotNil: [
		afterAssigning ifNotNil: [ :aBlock |
			afterAssigning := nil.
			aBlock value: key ] ].
	^ key
]

{ #category : #working }
SoilQueueTestRemovingQueue >> claim: aKey [

	| claimed |
	claimed := super claim: aKey.
	afterClaiming ifNotNil: [ :aBlock |
		afterClaiming := nil.
		aBlock value: aKey ].
	^ claimed
]
