import React from "react";

// Updates the height of a <textarea> when the value changes.
export const useAutoSizeTextArea = (
  id: string,
  textAreaRef: HTMLTextAreaElement | null,
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  value: any,
) => {
  React.useLayoutEffect(() => {
    const textArea = textAreaRef ?? document.getElementById(id);

    if (textArea && textArea.style && value) {
      // Batch DOM read/write to avoid layout thrashing on Mac
      textArea.style.height = "0";
      const scrollHeight = textArea.scrollHeight;
      textArea.style.height = `${10 + scrollHeight}px`;
    }
  }, [textAreaRef, value, id]);
};
