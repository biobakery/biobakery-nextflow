"""Stand-in for anadama2.document.

visualizations.py imports PweaveDocument inside one function. Point it at the
vendored document class so there is a single implementation in play.
"""

from biobakery_document import PweaveDocument, Document

__all__ = ["PweaveDocument", "Document"]
