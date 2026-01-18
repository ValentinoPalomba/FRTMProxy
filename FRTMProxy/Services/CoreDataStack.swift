import CoreData

final class CoreDataStack {
    static let shared = CoreDataStack()

    let container: NSPersistentContainer

    private init() {
        let model = Self.createManagedObjectModel()
        container = NSPersistentContainer(name: "FRTMProxy", managedObjectModel: model)
        container.loadPersistentStores { _, error in
            if let error = error {
                fatalError("Unresolved error \(error)")
            }
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
    }

    var viewContext: NSManagedObjectContext {
        container.viewContext
    }

    func newBackgroundContext() -> NSManagedObjectContext {
        let context = container.newBackgroundContext()
        context.undoManager = nil
        context.automaticallyMergesChangesFromParent = true
        return context
    }

    private static func createManagedObjectModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()

        let entity = NSEntityDescription()
        entity.name = "MitmFlowEntity"
        entity.managedObjectClassName = "MitmFlowEntity"

        var properties = [NSAttributeDescription]()

        let idAttr = NSAttributeDescription()
        idAttr.name = "id"
        idAttr.attributeType = .stringAttributeType
        idAttr.isOptional = false
        properties.append(idAttr)

        let eventAttr = NSAttributeDescription()
        eventAttr.name = "event"
        eventAttr.attributeType = .stringAttributeType
        eventAttr.isOptional = false
        properties.append(eventAttr)

        let timestampAttr = NSAttributeDescription()
        timestampAttr.name = "timestamp"
        timestampAttr.attributeType = .doubleAttributeType
        timestampAttr.isOptional = false
        properties.append(timestampAttr)

        let clientIPAttr = NSAttributeDescription()
        clientIPAttr.name = "clientIP"
        clientIPAttr.attributeType = .stringAttributeType
        clientIPAttr.isOptional = true
        properties.append(clientIPAttr)

        let clientPortAttr = NSAttributeDescription()
        clientPortAttr.name = "clientPort"
        clientPortAttr.attributeType = .integer32AttributeType
        clientPortAttr.isOptional = false
        properties.append(clientPortAttr)

        let requestDataAttr = NSAttributeDescription()
        requestDataAttr.name = "requestData"
        requestDataAttr.attributeType = .binaryDataAttributeType
        requestDataAttr.isOptional = true
        properties.append(requestDataAttr)

        let responseDataAttr = NSAttributeDescription()
        responseDataAttr.name = "responseData"
        responseDataAttr.attributeType = .binaryDataAttributeType
        responseDataAttr.isOptional = true
        properties.append(responseDataAttr)

        let breakpointDataAttr = NSAttributeDescription()
        breakpointDataAttr.name = "breakpointData"
        breakpointDataAttr.attributeType = .binaryDataAttributeType
        breakpointDataAttr.isOptional = true
        properties.append(breakpointDataAttr)

        entity.properties = properties
        model.entities = [entity]

        return model
    }
}
