import terminado
from tornado import web


class _StatusHandler(web.RequestHandler):
    """A handler for checking the status of the service."""

    def get(self):
        """Handle GET requests."""
        self.write({'code': 'ok', 'message': 'server is ready'})


def start(port, command):
    """Start the terminal application using the provided port and command.

    Return a function that must be used to close the app.
    """
    term_manager = terminado.UniqueTermManager(
        shell_command=[command], term_settings={'cwd': '/home/ubuntu'})
    handlers = [
        (r'/status', _StatusHandler),
        (r'/websocket', terminado.TermSocket, {'term_manager': term_manager}),
    ]
    app = web.Application(handlers)
    app.listen(port, '0.0.0.0')
    return term_manager.shutdown
