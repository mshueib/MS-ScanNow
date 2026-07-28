import 'dart:io';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

class PDFViewerScreen extends StatefulWidget {
  final String path;

  const PDFViewerScreen({super.key, required this.path});

  @override
  State<PDFViewerScreen> createState() => _PDFViewerScreenState();
}

class _PDFViewerScreenState extends State<PDFViewerScreen> {
  final PdfViewerController _controller = PdfViewerController();
  int _currentPage = 1;
  int _totalPages = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _share() async {
    await Share.shareXFiles(
      [XFile(widget.path)],
      text: 'Documento digitalizado',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _totalPages > 0
              ? 'Página $_currentPage de $_totalPages'
              : 'Visualizar PDF',
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            tooltip: 'Compartilhar',
            onPressed: _share,
          ),
        ],
      ),
      body: SfPdfViewer.file(
        File(widget.path),
        controller: _controller,
        onDocumentLoaded: (details) {
          setState(() => _totalPages = details.document.pages.count);
        },
        onPageChanged: (details) {
          setState(() => _currentPage = details.newPageNumber);
        },
        onDocumentLoadFailed: (details) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Erro ao abrir PDF: ${details.description}'),
            ),
          );
        },
      ),
    );
  }
}
