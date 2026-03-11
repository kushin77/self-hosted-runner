from function import main


def pubsub_entry(event, context):
    return main(event, context)
