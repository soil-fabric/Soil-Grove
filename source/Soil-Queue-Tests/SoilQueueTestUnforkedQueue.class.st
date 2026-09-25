"
A queue whose dispatcher starts its workers without forking them. They are registered the
way a started worker is, and they stay registered until someone runs them -- so a test can
count what the dispatcher started instead of catching a forked worker before it runs dry.
"
Class {
	#name : #SoilQueueTestUnforkedQueue,
	#superclass : #SoilQueue,
	#category : #'Soil-Queue-Tests'
}

{ #category : #'instance creation' }
SoilQueueTestUnforkedQueue class >> from: aQueue [
	"the same queue, only unforked. A live queue comes from its description, and the
	description knows one class to make"

	^ self basicNew
		copyFrom: aQueue;
		yourself
]

{ #category : #running }
SoilQueueTestUnforkedQueue >> startWorker [

	self workerStarting: (SoilQueueWorker on: self)
]
